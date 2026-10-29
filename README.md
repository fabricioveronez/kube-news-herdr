# Kube-News

Uma aplicação de notícias desenvolvida em NodeJS para demonstrar o uso de containers e Kubernetes.

## 📋 Sobre o Projeto

O projeto Kube-News é uma aplicação web simples desenvolvida em Node.js, projetada como exemplo para demonstrar o uso de contêineres. É um portal de notícias que permite criar, visualizar e gerenciar artigos através de uma interface web.

### 🚀 Funcionalidades Principais

- Listagem de notícias na página inicial
- Criação de novas notícias através de formulário
- Visualização detalhada de cada notícia
- API REST para inserção em massa de notícias
- Endpoints de health check para monitoramento
- Coleta de métricas para Prometheus

## 🛠️ Tecnologias Utilizadas

- **Backend**: Node.js com Express.js
- **Frontend**: EJS (Embedded JavaScript) como motor de templates
- **Banco de Dados**: PostgreSQL com Sequelize ORM
- **Monitoramento**: Prometheus (via express-prom-bundle)

## 📦 Estrutura do Projeto

```
/
├── src/                      # Código-fonte principal
│   ├── models/               # Modelos de dados
│   │   └── post.js           # Definição do modelo Post
│   ├── views/                # Templates EJS
│   │   ├── partial/          # Componentes parciais (header, footer)
│   │   ├── edit-news.ejs     # Formulário de edição
│   │   ├── index.ejs         # Página principal
│   │   └── view-news.ejs     # Visualização de notícia
│   ├── static/               # Arquivos estáticos (CSS, imagens)
│   ├── middleware.js         # Middlewares personalizados
│   ├── server.js             # Ponto de entrada da aplicação
│   ├── system-life.js        # Endpoints de health check
│   └── package.json          # Dependências
│   ├── Dockerfile            # Imagem da aplicação
│   └── .dockerignore
├── k8s/                      # Manifestos Kubernetes (EKS)
├── docker-compose.yml        # Ambiente local (app + PostgreSQL)
├── popula-dados.http         # Arquivo para popular o banco com dados de exemplo
└── README.md                 # Documentação
```

## 🔧 Configuração

### Pré-requisitos

- Node.js
- PostgreSQL
- Docker (opcional, para containerização)
- Kubernetes (opcional, para orquestração)

### Variáveis de Ambiente

Para configurar a aplicação, defina as seguintes variáveis de ambiente:

| Variável | Descrição | Valor Padrão |
|----------|-----------|--------------|
| DB_DATABASE | Nome do banco de dados | kubedevnews |
| DB_USERNAME | Usuário do banco de dados | kubedevnews |
| DB_PASSWORD | Senha do usuário | Pg#123 |
| DB_HOST | Endereço do banco de dados | localhost |
| DB_PORT | Porta do banco de dados | 5432 |
| DB_SSL_REQUIRE | Habilitar SSL para conexão | false |

## 🚀 Instalação e Execução

### Execução Local

1. Clone o repositório
2. Instale as dependências:
   ```bash
   cd src
   npm install
   ```
3. Configure as variáveis de ambiente necessárias
4. Inicie a aplicação:
   ```bash
   npm start
   ```
5. Acesse a aplicação em [http://localhost:8080](http://localhost:8080)

### Build da Imagem Docker

O `Dockerfile` fica em `src/`, que também é o contexto de build:

```bash
docker build -t kube-news ./src
```

A imagem roda como o usuário não-root `1000` e expõe a porta `8080`.

### Execução Local com Docker Compose

O `docker-compose.yml` na raiz sobe a aplicação junto com um PostgreSQL 16:

```bash
docker compose up -d --build
```

A aplicação fica disponível em [http://localhost:8080](http://localhost:8080). O banco é **efêmero** (sem volume): os dados são perdidos ao executar `docker compose down`. A porta do PostgreSQL não é publicada no host.

Para encerrar:

```bash
docker compose down
```

### População de Dados de Exemplo

Utilize o arquivo `popula-dados.http` para inserir notícias de exemplo:

```bash
# Com uma ferramenta como o REST Client no VS Code ou curl
POST http://localhost:8080/api/post
Content-Type: application/json
# Conteúdo do arquivo popula-dados.http
```

## ☸️ Deploy no EKS

Os manifestos em `k8s/` implantam a aplicação no EKS conectando a um RDS PostgreSQL externo:

| Arquivo | Objeto |
|---------|--------|
| `configmap.yaml` | ConfigMap `kube-news-config` (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_SSL_REQUIRE: "true"`) |
| `secret.yaml` | Secret `kube-news-db` (`DB_USERNAME`, `DB_PASSWORD`) |
| `deployment.yaml` | Deployment `kube-news` (2 réplicas, probes em `/health` e `/ready`) |
| `service.yaml` | Service `kube-news` do tipo `LoadBalancer` (porta 80 → 8080) |

Os manifestos não definem namespace; ele é escolhido no `kubectl apply`. Provisionamento de EKS, RDS, VPC, Security Groups e ECR está fora deste escopo.

1. Faça o build e o push da imagem para o ECR (use sempre uma tag explícita, nunca `latest`):
   ```bash
   aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com
   docker build -t <account_id>.dkr.ecr.<region>.amazonaws.com/kube-news:<tag> ./src
   docker push <account_id>.dkr.ecr.<region>.amazonaws.com/kube-news:<tag>
   ```
2. Substitua os placeholders:
   - `k8s/deployment.yaml`: imagem do ECR com a tag publicada
   - `k8s/configmap.yaml`: endpoint do RDS em `DB_HOST`
   - `k8s/secret.yaml`: `DB_USERNAME` e `DB_PASSWORD`
3. Aplique os manifestos:
   ```bash
   kubectl apply -f k8s/ -n <namespace>
   ```
4. Obtenha o endereço do load balancer:
   ```bash
   kubectl get service kube-news -n <namespace>
   ```

> ⚠️ **Não versione credenciais reais.** Substitua os valores do `k8s/secret.yaml` apenas no momento do deploy e não faça commit dessas alterações.

Rollback: `kubectl rollout undo deployment/kube-news -n <namespace>`.

### Network Load Balancer (opcional)

Sem anotações, o EKS cria um Classic Load Balancer. Para usar um NLB, adicione ao `metadata` do `k8s/service.yaml`:

```yaml
  annotations:
    # Com o AWS Load Balancer Controller instalado:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    # Sem o controller (provider legado):
    # service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

## ✅ Validação

### Docker Compose

```bash
docker compose up -d --build
curl -s http://localhost:8080/health      # {"state":"up",...}
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/ready    # 200
curl -s http://localhost:8080/metrics | grep http_requests_total
docker compose ps                         # app sem reinícios
docker compose down
```

Em seguida, envie o conteúdo de `popula-dados.http` para `POST /api/post` e confirme que as notícias aparecem em `GET /`. Após `docker compose down` e um novo `up`, a página inicial deve voltar ao estado vazio.

### Manifestos Kubernetes (kind + dry-run de servidor)

Requer [kind](https://kind.sigs.k8s.io/) e `kubectl`:

```bash
kind create cluster --name kube-news-validate
kubectl apply -f k8s/ --dry-run=server --context kind-kube-news-validate
kind delete cluster --name kube-news-validate
```

O dry-run deve reportar os quatro objetos como `(server dry run)` sem criar nada. O `--context` explícito evita aplicar por engano em outro cluster. O dry-run não valida o runtime (pull de imagem, probes); a imagem é validada de verdade pelo Docker Compose.

## 📊 Monitoramento e Health Checks

A aplicação disponibiliza endpoints para monitoramento e também recursos para simular cenários de falha, muito úteis para testar a resiliência em ambientes Kubernetes:

### Endpoints de Monitoramento
- `/health` - Verifica o estado atual da aplicação (retorna status da aplicação e hostname da máquina)
- `/ready` - Verifica se a aplicação está pronta para receber tráfego
- `/metrics` - Métricas do Prometheus (geradas pelo express-prom-bundle)

### Simulação de Falhas (Chaos Engineering)
- `/unhealth` - (PUT) Altera o estado da aplicação para não saudável. Todas as requisições subsequentes receberão status code 500.
- `/unreadyfor/:seconds` - (PUT) Simula indisponibilidade temporária por um número específico de segundos. Durante este período, o endpoint `/ready` retornará status code 500.

Estes recursos de simulação de falhas são extremamente úteis para testar:
- Comportamento de probes de liveness e readiness no Kubernetes
- Políticas de retry e circuit breaker
- Mecanismos de failover
- Resiliência geral da sua infraestrutura

## 🔒 Modelo de Dados

O projeto utiliza um único modelo `Post` com os seguintes campos:

| Campo | Tipo | Descrição |
|-------|------|-----------|
| title | String | Título da notícia (limite: 30 caracteres) |
| summary | String | Resumo da notícia (limite: 50 caracteres) |
| content | String | Conteúdo completo (limite: 2000 caracteres) |
| publishDate | Date | Data de publicação |


