## Why

O Kube-News precisa de uma infraestrutura na AWS para rodar no EKS com o banco em um RDS PostgreSQL, mas hoje nada disso existe como código: a change `containerize-app-eks` deixa explicitamente fora do escopo o provisionamento de EKS, RDS, VPC e Security Groups. Sem essa base, os manifestos Kubernetes não têm onde ser aplicados e a pipeline de deploy não tem um cluster nem um banco de destino.

## What Changes

- Novo projeto Terraform em `terraform/` (minúsculo), organizado em um root module que compõe três módulos locais em `terraform/modules/`: `network`, `eks` e `rds`. Nenhum módulo de comunidade (Terraform Registry) é utilizado.
- Provider `hashicorp/aws` na versão mais recente (`~> 6.70`), com `.terraform.lock.hcl` versionado.
- Região parametrizável por `var.region`, com padrão `us-east-1` (Virgínia do Norte).
- Rede própria e independente: VPC dedicada em **duas zonas de disponibilidade**, com subnets públicas, privadas e de banco em cada AZ, Internet Gateway e NAT Gateway por AZ (alta disponibilidade por padrão, com opção de NAT único para reduzir custo).
- Cluster EKS na versão mais recente de Kubernetes disponível na AWS (resolvida dinamicamente, com possibilidade de fixar por variável), autenticação via API (access entries), managed node group nas subnets privadas e addons gerenciados (`vpc-cni`, `kube-proxy`, `coredns`).
- RDS PostgreSQL privado, Multi-AZ por padrão (com opção de desligar), acessível na porta 5432 apenas a partir do cluster EKS, com credenciais fornecidas por variáveis (senha sensível e obrigatória, sem Secrets Manager).
- State remoto em backend S3 com lock nativo (`use_lockfile`), via configuração parcial (`backend.hcl` não versionado).
- Outputs para a pipeline de deploy: dados do cluster (nome, endpoint, região, comando de kubeconfig) e do banco (endpoint, porta, nome, usuário).
- Plano de validação estático: `terraform fmt`, `terraform init -backend=false` e `terraform validate`, sem `plan` nem `apply`.
- Documentação de uso em `terraform/README.md` e entradas de Terraform no `.gitignore`.

## Capabilities

### New Capabilities
- `terraform-foundation`: estrutura do projeto Terraform (pastas, módulos locais, versões de Terraform e provider, lock file), região parametrizável, backend S3, variáveis/outputs do root, documentação e o plano de validação (`fmt` + `validate`).
- `aws-network`: VPC própria em duas AZs com subnets públicas, privadas e de banco, roteamento, NAT Gateway e tags de descoberta de load balancer para o EKS.
- `eks-cluster`: cluster EKS na versão mais recente disponível, IAM, autenticação por access entries, managed node group e addons gerenciados.
- `rds-postgresql`: instância RDS PostgreSQL privada, Multi-AZ configurável, subnet group, Security Group restrito ao cluster e credenciais por variáveis.

### Modified Capabilities
<!-- Nenhuma: não há specs existentes em openspec/specs/. -->

## Impact

- **Arquivos novos**: `terraform/` (root module, `backend.hcl.example`, `terraform.tfvars.example`, `.terraform.lock.hcl`, `README.md`) e `terraform/modules/{network,eks,rds}/`.
- **Arquivos alterados**: `.gitignore` (estado local, `.terraform/`, `terraform.tfvars`, `backend.hcl`).
- **Código da aplicação e change `containerize-app-eks`**: sem alterações. Manifestos Kubernetes, build/push da imagem (Docker Hub) e pipeline de deploy ficam fora do escopo.
- **Pré-requisito externo**: um bucket S3 para o state, criado fora do Terraform antes do `terraform init`.
- **Custos AWS** ao aplicar: control plane do EKS, instâncias EC2 dos nós, NAT Gateways (2 por padrão), RDS Multi-AZ e tráfego. Esta change não executa `plan` nem `apply`.
- **Ferramentas para validação**: Terraform >= 1.11 e acesso à internet para baixar o provider (sem credenciais AWS).
