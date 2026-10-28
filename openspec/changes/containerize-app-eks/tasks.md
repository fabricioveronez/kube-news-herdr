## 1. Imagem de container

- [ ] 1.1 Criar `src/.dockerignore` excluindo `node_modules`, `npm-debug.log*`, `.env*`, `Dockerfile` e `.dockerignore`
- [ ] 1.2 Criar `src/Dockerfile` em estágio único: `node:22-alpine`, `WORKDIR /app`, `COPY package*.json`, `npm ci --omit=dev`, `COPY . .`, `USER 1000`, `EXPOSE 8080`, `CMD ["node", "server.js"]` (sem `tini`)
- [ ] 1.3 Executar `docker build -t kube-news ./src` e confirmar que o build conclui
- [ ] 1.4 Confirmar que o usuário da imagem é `1000` e que `8080/tcp` está em `ExposedPorts`
- [ ] 1.5 Confirmar que `src/package.json` e `src/package-lock.json` não foram alterados

## 2. Ambiente local com Docker Compose

- [ ] 2.1 Criar `docker-compose.yml` na raiz com o serviço `postgres` (`postgres:16-alpine`, credenciais `kubedevnews`/`Pg#123`, healthcheck `pg_isready`, sem volumes e sem porta publicada)
- [ ] 2.2 Adicionar o serviço `app` (`build.context: ./src`, porta `8080:8080`, variáveis `DB_*` explícitas com `DB_HOST=postgres` e `DB_SSL_REQUIRE=false`, `depends_on` com `condition: service_healthy`)
- [ ] 2.3 Corrigir a URL do `popula-dados.http` de `4503` para `8080`
- [ ] 2.4 Executar `docker compose config` e confirmar que nenhum serviço declara volumes

## 3. Validação do ambiente local

- [ ] 3.1 Executar `docker compose up -d --build` e aguardar `GET /health` responder HTTP 200
- [ ] 3.2 Validar `GET /health` (`"state":"up"`), `GET /ready` (200) e `GET /metrics` (contém `http_requests_total`)
- [ ] 3.3 Validar `GET /` (estado vazio) e `GET /styles/main.css` (200)
- [ ] 3.4 Enviar o payload de `popula-dados.http` em `POST /api/post` e confirmar "Kubernetes na Nuvem" em `GET /`
- [ ] 3.5 Enviar `POST /post` via formulário e confirmar o redirecionamento e o novo título em `GET /`
- [ ] 3.6 Validar `GET /post/1` (200)
- [ ] 3.7 Confirmar que o container `app` não reiniciou (`docker compose ps`)
- [ ] 3.8 Executar `docker compose down`, subir novamente e confirmar que `GET /` está vazio (banco efêmero); encerrar com `docker compose down`

## 4. Manifestos Kubernetes

- [ ] 4.1 Criar `k8s/configmap.yaml` (`kube-news-config`) com `DB_HOST` placeholder do RDS, `DB_PORT`, `DB_DATABASE` e `DB_SSL_REQUIRE: "true"`
- [ ] 4.2 Criar `k8s/secret.yaml` (`kube-news-db`, `Opaque`, `stringData`) com `DB_USERNAME` e `DB_PASSWORD` placeholders
- [ ] 4.3 Criar `k8s/deployment.yaml` (`kube-news`): 2 réplicas, imagem ECR com tag explícita, `envFrom`, porta 8080, liveness `/health`, readiness `/ready`, resources, `runAsNonRoot`/`runAsUser: 1000`, `allowPrivilegeEscalation: false`, `drop: ["ALL"]`
- [ ] 4.4 Criar `k8s/service.yaml` (`kube-news`): `type: LoadBalancer`, porta 80 → 8080, selector `app: kube-news`
- [ ] 4.5 Confirmar que nenhum manifesto define `kind: Namespace` nem `metadata.namespace`

## 5. Validação dos manifestos com kind

- [ ] 5.1 Criar o cluster `kind create cluster --name kube-news-validate`
- [ ] 5.2 Executar `kubectl apply -f k8s/ --dry-run=server --context kind-kube-news-validate` e confirmar código 0 com os quatro objetos `(server dry run)`
- [ ] 5.3 Confirmar que nenhum objeto `kube-news` foi criado no namespace `default`
- [ ] 5.4 Remover o cluster com `kind delete cluster --name kube-news-validate`

## 6. Documentação

- [ ] 6.1 Atualizar o `README.md` com o build da imagem (`docker build ./src`) e a execução local via `docker compose up`
- [ ] 6.2 Documentar no `README.md` o deploy no EKS: push para o ECR, substituição dos placeholders, `kubectl apply -f k8s/ -n <namespace>`, aviso para não versionar credenciais reais e anotações opcionais para NLB
- [ ] 6.3 Documentar no `README.md` os passos de validação (Compose e kind com dry-run)
