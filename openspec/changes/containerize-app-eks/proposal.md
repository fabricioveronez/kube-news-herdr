## Why

O Kube-News precisa rodar como container em um cluster EKS, com o banco de dados em um RDS PostgreSQL externo. Hoje o repositório não tem Dockerfile, Docker Compose nem manifestos Kubernetes, então não há como empacotar a aplicação, executá-la localmente com banco junto, nem implantá-la no cluster.

## What Changes

- Novo `src/Dockerfile` (estágio único, sem multi-stage, sem `tini`) que gera a imagem da aplicação usando `src/` como contexto de build.
- Novo `src/.dockerignore` para manter o contexto de build limpo (em especial, sem `node_modules` local).
- Novo `docker-compose.yml` na raiz do projeto, executando a aplicação junto com um PostgreSQL efêmero (sem volume) para desenvolvimento local.
- Novos manifestos Kubernetes em `k8s/` para o deploy da aplicação no EKS: ConfigMap, Secret comum, Deployment e Service do tipo `LoadBalancer`. Os manifestos não definem namespace.
- Ajuste do `popula-dados.http` para apontar para a porta real da aplicação (`8080`, em vez de `4503`).
- Atualização do `README.md` com instruções de build, execução local via Compose e deploy no EKS.
- Processo de validação obrigatório: execução real via Docker Compose com smoke tests HTTP, e validação dos manifestos com `kubectl apply --dry-run=server` contra um cluster `kind` local.

Nenhuma alteração no código da aplicação (`src/*.js`, `src/views`, `src/package*.json`).

## Capabilities

### New Capabilities
- `container-image`: imagem de container da aplicação (Dockerfile e `.dockerignore` em `src/`).
- `local-compose-environment`: ambiente local de desenvolvimento via Docker Compose com aplicação e PostgreSQL efêmero, incluindo os smoke tests que o validam.
- `kubernetes-deployment`: manifestos de deploy da aplicação no EKS conectando a um RDS externo, incluindo a validação via `kind` + dry-run de servidor.

### Modified Capabilities
<!-- Nenhuma: não há specs existentes em openspec/specs/. -->

## Impact

- **Arquivos novos**: `src/Dockerfile`, `src/.dockerignore`, `docker-compose.yml`, `k8s/configmap.yaml`, `k8s/secret.yaml`, `k8s/deployment.yaml`, `k8s/service.yaml`.
- **Arquivos alterados**: `popula-dados.http` (porta), `README.md` (documentação).
- **Código da aplicação**: sem alterações. Dependências antigas e vulnerabilidades existentes são intencionais e permanecem intocadas.
- **Infraestrutura fora do escopo**: provisionamento de EKS, RDS, VPC, Security Groups, repositório ECR, Ingress Controller e pipeline CI/CD.
- **Ferramentas necessárias para validação**: Docker com Compose, `kind` e `kubectl` na máquina local.
