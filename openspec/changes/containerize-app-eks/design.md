## Context

Kube-News é uma aplicação Node.js (Express + EJS + Sequelize/PostgreSQL) sem etapa de build. Pontos do código que condicionam o empacotamento:

- Porta `8080` fixa em `src/server.js`; não existe variável `PORT`.
- `express.static('static')` e o diretório de views são resolvidos relativos ao diretório de trabalho do processo.
- Toda a configuração de banco vem de variáveis de ambiente: `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_SSL_REQUIRE`.
- `models.initDatabase()` chama `seque.sync({ alter: true })` sem `await`; se o banco não estiver acessível na subida, a rejeição não tratada derruba o processo.
- `/health` (liveness; passa a retornar 500 após `PUT /unhealth`), `/ready` (readiness; retorna 500 durante `PUT /unreadyfor/:seconds`) e `/metrics` (Prometheus).
- Com `DB_SSL_REQUIRE=true`, a conexão usa SSL com `rejectUnauthorized: false`, compatível com o `rds.force_ssl` padrão do RDS sem embutir o CA bundle da AWS.
- Dependências antigas e falhas de segurança foram introduzidas de propósito (commits "Adicionando vulnerabilidades") e não devem ser corrigidas.

Destino: EKS com RDS PostgreSQL externo. Ambiente local: Docker Compose com PostgreSQL efêmero.

## Goals / Non-Goals

**Goals:**
- Uma única imagem, idêntica para local e EKS; o ambiente muda apenas por variáveis de ambiente.
- Subir aplicação + banco localmente com um único `docker compose up`.
- Manifestos Kubernetes mínimos e válidos para o deploy da aplicação no EKS.
- Validação reproduzível: Compose executado de verdade com smoke tests; manifestos validados por dry-run de servidor no `kind`.

**Non-Goals:**
- Alterar o código da aplicação, atualizar dependências ou corrigir vulnerabilidades.
- Provisionar EKS, RDS, VPC, Security Groups, ECR ou pipeline CI/CD.
- Ingress / Ingress Controller, HPA, PodDisruptionBudget, NetworkPolicy.
- Multi-stage build, `tini`/init no container, tratamento de `SIGTERM`.
- Persistência de dados no ambiente local.
- Deploy real da aplicação no `kind` (apenas dry-run).

## Decisions

### D1. Dockerfile em `src/`, contexto de build `./src`
O Dockerfile e o `.dockerignore` ficam em `src/`. O Docker só lê o `.dockerignore` da raiz do contexto, por isso ele precisa estar em `src/`. Como `openspec/`, `.claude/`, `.codex/` e `.git` estão fora do contexto, o `.dockerignore` só precisa excluir `node_modules`, logs do npm, `.env*` e o próprio Dockerfile/dockerignore.
- *Alternativa*: Dockerfile na raiz com contexto `.` — descartada por decisão do usuário.

### D2. Estágio único, sem multi-stage
A aplicação não tem transpilação, bundler nem dependências nativas, então o multi-stage traria pouco ganho. Estrutura:
1. `FROM node:22-alpine` (LTS, base pequena).
2. `WORKDIR /app`.
3. `COPY package*.json ./` e `RUN npm ci --omit=dev` (camada de dependências separada para cache; `npm ci` respeita o `package-lock.json`, preservando as versões intencionalmente antigas).
4. `COPY . .` (o conteúdo de `src/` cai direto em `/app`, que é o diretório de trabalho esperado por `static/` e `views/`).
5. `USER 1000` (o usuário `node` da imagem oficial, em forma **numérica** — ver D6).
6. `EXPOSE 8080` e `CMD ["node", "server.js"]` em forma exec.
- *Alternativa*: `node:22-slim` ou distroless — alpine escolhido pelo tamanho e por ter `wget` (busybox) disponível para depuração.

### D3. Sem `tini`
Por decisão do usuário, o Node roda diretamente como PID 1. Ver riscos.

### D4. Docker Compose na raiz, PostgreSQL efêmero
- Serviço `postgres`: imagem `postgres:16-alpine`, `POSTGRES_DB=kubedevnews`, `POSTGRES_USER=kubedevnews`, `POSTGRES_PASSWORD=Pg#123` (valores iguais aos defaults da aplicação). **Sem volumes**. Healthcheck com `pg_isready -U kubedevnews -d kubedevnews`. Porta do banco não publicada no host.
- Serviço `app`: `build.context: ./src`, porta `8080:8080`, variáveis `DB_HOST=postgres`, `DB_PORT=5432`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` e `DB_SSL_REQUIRE=false` explícitas, e `depends_on: postgres: condition: service_healthy`. Isso elimina a corrida em que a aplicação sobe antes do banco aceitar conexões e morre no `sync()`.
- Valores com `#` devem ficar entre aspas no YAML.
- *Alternativa*: `restart: on-failure` em vez do healthcheck — descartada; o healthcheck é determinístico.

### D5. Manifestos em `k8s/`, sem namespace
Arquivos: `configmap.yaml`, `secret.yaml`, `deployment.yaml`, `service.yaml`. Nenhum define `kind: Namespace` nem `metadata.namespace`; quem aplica escolhe com `-n`. Na validação, tudo cai no namespace `default` do `kind`, evitando a falha de dry-run de servidor quando o Namespace ainda não existe.
- **ConfigMap `kube-news-config`**: `DB_HOST` (placeholder do endpoint RDS), `DB_PORT: "5432"`, `DB_DATABASE: "kubedevnews"`, `DB_SSL_REQUIRE: "true"`.
- **Secret `kube-news-db`** (tipo `Opaque`, via `stringData`): `DB_USERNAME` e `DB_PASSWORD` com placeholders. Secret comum, sem External Secrets/Secrets Manager.
- **Deployment `kube-news`**: 2 réplicas; imagem placeholder no formato ECR (`<account_id>.dkr.ecr.<region>.amazonaws.com/kube-news:<tag>`), nunca `latest`; `envFrom` com o ConfigMap e o Secret; `containerPort: 8080`; `livenessProbe` HTTP em `/health` e `readinessProbe` HTTP em `/ready`; `resources` com requests e limits de CPU/memória; securityContext conforme D6.
- **Service `kube-news`**: `type: LoadBalancer`, porta `80` → `targetPort: 8080`. No EKS isso provisiona um load balancer da AWS sem precisar de Ingress.
- Labels consistentes (`app: kube-news`) ligando Deployment e Service.
- *Alternativas*: `NodePort` (exige nó público e regra de SG na faixa 30000–32767); Kustomize/Helm (desnecessário para quatro arquivos).

### D6. Usuário não-root numérico
`runAsNonRoot: true` exige UID numérico para o kubelet verificar o usuário. Com `USER node` (nome), o pod falharia com *"image has non-numeric user (node), cannot verify user is non-root"* — erro que o dry-run **não** detecta. Por isso a imagem usa `USER 1000` e o pod declara `runAsNonRoot: true` e `runAsUser: 1000`. O container define `allowPrivilegeEscalation: false` e remove todas as capabilities.

### D7. Estratégia de validação
- **Compose (execução real)**: `docker compose up -d --build`, aguardar `/health` responder, executar smoke tests HTTP (ver spec `local-compose-environment`), depois `docker compose down` e novo `up` para provar que o banco é efêmero.
- **Kubernetes (somente validação)**: `kind create cluster --name kube-news-validate`, `kubectl apply -f k8s/ --dry-run=server --context kind-kube-news-validate`, `kind delete cluster --name kube-news-validate`. Dry-run de servidor é escolhido em vez de `client` porque valida contra o schema real do API server. O `--context` explícito impede aplicar por engano em outro cluster configurado no kubeconfig.

## Risks / Trade-offs

- **[Node como PID 1 ignora `SIGTERM`]** → Encerramento lento: ~30s por pod em rollouts no EKS (`terminationGracePeriodSeconds` padrão) e ~10s no `docker compose down`. Risco aceito; correção futura possível com `process.on('SIGTERM')` no código.
- **[`sync({ alter: true })` concorrente entre réplicas]** → Cada pod executa DDL ao subir; com 2 réplicas iniciando juntas contra o RDS pode haver `ALTER TABLE` concorrente. Tabela pequena e operação idempotente; risco aceito.
- **[RDS inacessível na subida]** → O processo morre (rejeição não tratada) e o pod entra em CrashLoopBackOff até o RDS responder. Aceitável; depende de rede e Security Group fora do escopo.
- **[Dry-run não valida o runtime]** → Erros de kubelet (pull de imagem, securityContext, probes) não aparecem no dry-run. Mitigação parcial: D6 trata o caso conhecido de `runAsNonRoot`; a imagem é validada de verdade pelo Compose.
- **[Secret com placeholders versionado]** → Risco de alguém commitar credenciais reais em `k8s/secret.yaml`. Mitigação: valores claramente placeholder e aviso no README para substituir só no momento do deploy.
- **[Service `LoadBalancer` sem anotações]** → Sem o AWS Load Balancer Controller, o EKS usa o provider legado e cria um Classic Load Balancer. Funciona; o README indica as anotações para usar NLB se desejado.
- **[Versão do Node vs dependências antigas]** → `node:22-alpine` com dependências de 2022. A validação via Compose é o que confirma a compatibilidade; se falhar, ajustar a tag da imagem base, não as dependências.

## Migration Plan

1. Build e push da imagem para o ECR (fora do escopo automatizar): `docker build -t <ecr>/kube-news:<tag> ./src`.
2. Substituir placeholders de imagem, `DB_HOST` e credenciais.
3. `kubectl apply -f k8s/ -n <namespace>`.
4. Rollback: `kubectl rollout undo deployment/kube-news -n <namespace>` ou reaplicar a tag anterior.

## Open Questions

Nenhuma no momento.
