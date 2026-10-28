## Context

O Kube-News é uma aplicação Node.js que lê toda a configuração de banco por variáveis de ambiente (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_SSL_REQUIRE`). Com `DB_SSL_REQUIRE=true`, ela conecta com SSL e `rejectUnauthorized: false`, o que é compatível com o `rds.force_ssl=1` padrão do RDS PostgreSQL 15+. O driver `pg@8.7.3` suporta `scram-sha-256`, padrão das versões atuais do PostgreSQL no RDS.

A change `containerize-app-eks` cobre a imagem e os manifestos Kubernetes (Service `type: LoadBalancer`, 2 réplicas, probes) e deixa fora do escopo toda a infraestrutura AWS. Esta change entrega essa infraestrutura. Os manifestos serão aplicados depois por uma pipeline; a imagem será publicada no Docker Hub.

Fatos verificados em 28/10/2026:
- Última versão do provider `hashicorp/aws`: **6.70.0**. Terraform local: 1.15.6.
- Versões EKS em `us-east-1`: **1.37** (mais recente e default), 1.36, 1.35 e 1.34 em suporte padrão.
- RDS PostgreSQL: até **18.6**; `db.t4g.micro` aceita Multi-AZ nessa versão.
- O lock via DynamoDB do backend S3 está deprecated; o recomendado é `use_lockfile = true` (Terraform >= 1.11).

Não haverá credenciais AWS na validação: o projeto é validado apenas estaticamente.

## Goals / Non-Goals

**Goals:**
- Provisionar, com um único root module, VPC + EKS + RDS PostgreSQL prontos para receber o deploy do Kube-News.
- Código organizado em módulos locais, sem módulos de comunidade.
- Alta disponibilidade por padrão em duas AZs (NAT por AZ, nós distribuídos, RDS Multi-AZ), com flags para reduzir custo.
- Região parametrizável com padrão `us-east-1`; versão do Kubernetes sempre a mais recente por padrão.
- Expor os outputs que a pipeline precisa para configurar o kubeconfig e os manifestos.
- Validação reproduzível com `terraform fmt` e `terraform validate`, sem credenciais AWS.

**Non-Goals:**
- Manifestos Kubernetes, build/push da imagem, Docker Hub, ECR e pipeline CI/CD.
- AWS Load Balancer Controller, Ingress, IRSA/Pod Identity, Cluster Autoscaler/Karpenter.
- Secrets Manager, KMS customer-managed, bastion host, VPN.
- Criação do bucket S3 do state pelo próprio Terraform.
- Múltiplos ambientes (workspaces, `envs/dev|prod`).
- Executar `terraform plan` ou `terraform apply`.

## Decisions

### D1. Estrutura: root module + módulos locais
```
terraform/
├── backend.tf               backend "s3" (configuração parcial)
├── backend.hcl.example      bucket + region do state (o backend.hcl real não é versionado)
├── versions.tf              required_version e required_providers
├── providers.tf             provider "aws" com region e default_tags
├── variables.tf
├── main.tf                  module "network" → module "eks" → module "rds"
├── outputs.tf
├── terraform.tfvars.example
├── .terraform.lock.hcl
├── README.md
└── modules/
    ├── network/  (main.tf, variables.tf, outputs.tf)
    ├── eks/      (main.tf, iam.tf, addons.tf, variables.tf, outputs.tf)
    └── rds/      (main.tf, variables.tf, outputs.tf)
```
Os módulos não declaram `provider` nem `backend`; cada um tem um `versions.tf` só com `required_providers` (aws), herdando o provider do root. Fluxo de dados:
```
network ──vpc_id, private_subnet_ids──────────▶ eks ──cluster_security_group_id──▶ rds
   └──────vpc_id, database_subnet_ids───────────────────────────────────────────────┘
```
- *Alternativa*: um único diretório plano — descartada, o usuário quer estrutura de módulos.
- *Alternativa*: módulos `terraform-aws-modules/*` — descartada por requisito.

### D2. Versões
- `required_version = ">= 1.11"` (mínimo para `use_lockfile` no backend S3).
- `hashicorp/aws` com `version = "~> 6.70"` (mais recente na data, aceita patches e minors 6.x).
- `.terraform.lock.hcl` versionado, com hashes para `linux_amd64`, `darwin_arm64` e `darwin_amd64` via `terraform providers lock`, para a pipeline (Linux) e o desenvolvimento local (macOS) usarem o mesmo provider.

### D3. Provider e região
`provider "aws" { region = var.region }` com `var.region` padrão `"us-east-1"`. `default_tags` aplicam `Project = var.project_name` e `ManagedBy = "terraform"` a todos os recursos. `var.project_name` (padrão `"kube-news"`) é o prefixo de nomes.

### D4. Backend S3 com configuração parcial
```hcl
terraform {
  backend "s3" {
    key          = "kube-news/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
```
`bucket` e `region` vêm de `backend.hcl` (`terraform init -backend-config=backend.hcl`); há um `backend.hcl.example` versionado. O bloco `backend` não aceita variáveis, e o nome do bucket é globalmente único, então ele não pode ficar fixo no repositório. A região do backend é independente de `var.region`. O bucket é criado fora do Terraform (README documenta criação com versionamento e bloqueio de acesso público).
- *Alternativa*: root `bootstrap/` com state local criando o bucket — descartada por adicionar um segundo root e dois applys.
- *Alternativa*: DynamoDB para lock — descartada, está deprecated.

### D5. Rede: duas AZs, três camadas
- AZs: `data "aws_availability_zones"` (`state = "available"`) e `slice(names, 0, 2)` — sempre duas AZs da região escolhida.
- VPC `var.vpc_cidr` (padrão `10.0.0.0/16`), com `enable_dns_support` e `enable_dns_hostnames` (exigidos pelo EKS e pelo endpoint privado).
- Subnets `/24` calculadas com `cidrsubnet(var.vpc_cidr, 8, n)`:

| Camada | AZ a | AZ b | Rota padrão | Tag |
|---|---|---|---|---|
| public | n=0 | n=1 | IGW | `kubernetes.io/role/elb = 1` |
| private | n=10 | n=11 | NAT da própria AZ | `kubernetes.io/role/internal-elb = 1` |
| database | n=20 | n=21 | nenhuma (sem saída à internet) | — |

- Subnets públicas com `map_public_ip_on_launch = true` (necessário para os NAT/LB; nenhum nó roda nelas).
- NAT: `var.single_nat_gateway` (padrão `false`). `false` → um NAT + EIP por AZ, cada route table privada aponta para o NAT da sua AZ; `true` → um único NAT na primeira AZ para todas.
- Uma route table pública compartilhada, uma por subnet privada e uma compartilhada para database (só rota local).
- As tags de role são o que permite ao Service `LoadBalancer` da outra change descobrir as subnets. A tag `kubernetes.io/cluster/<nome>` não é necessária nas versões atuais do EKS e não é usada, evitando acoplar o módulo de rede ao nome do cluster.

### D6. EKS
- **Versão**: `var.kubernetes_version` (padrão `null`). Com `null`, usa a maior versão em `STANDARD_SUPPORT` de `data "aws_eks_cluster_versions"`. Como as versões são strings (`"1.37"`), a maior é calculada numericamente pelo componente minor (`"1.${max([...tonumber(split(".", v)[1])]...)}"`), não por ordenação lexicográfica (que poria `1.4` acima de `1.37`). Se a variável for informada, prevalece (`coalesce`).
- **IAM**: role do cluster (`eks.amazonaws.com`, `sts:AssumeRole` + `sts:TagSession`) com `AmazonEKSClusterPolicy`; role dos nós (`ec2.amazonaws.com`) com `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` e `AmazonEC2ContainerRegistryReadOnly`. O cluster e o node group têm `depends_on` nos attachments, para que a deleção não perca permissões antes de limpar ENIs/SGs.
- **Cluster**: subnets privadas; `endpoint_private_access = true`, `endpoint_public_access = true`, `public_access_cidrs = var.cluster_public_access_cidrs` (padrão `["0.0.0.0/0"]`), permitindo que a pipeline e o usuário rodem `kubectl`.
- **Acesso**: `access_config { authentication_mode = "API", bootstrap_cluster_creator_admin_permissions = true }`. Quem executa o `apply` vira admin. Para outros principals (ex.: role da pipeline), `var.cluster_admin_principal_arns` (padrão `[]`) cria `aws_eks_access_entry` + `aws_eks_access_policy_association` com `AmazonEKSClusterAdminPolicy` em escopo `cluster`.
- **Node group**: managed, subnets privadas das duas AZs, `ami_type = "AL2023_x86_64_STANDARD"`, `capacity_type = "ON_DEMAND"`, `instance_types = var.node_instance_types` (padrão `["t3.medium"]`), escala `var.node_desired_size/min/max` (padrão 2/2/4). `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` para não brigar com um autoscaler futuro. A versão do node group acompanha a do cluster.
- **Addons**: `vpc-cni`, `kube-proxy` e `coredns` como `aws_eks_addon`, cada um com versão vinda de `data "aws_eks_addon_version"` (`most_recent = true`, `kubernetes_version` do cluster) e `resolve_conflicts_on_create/update = "OVERWRITE"`. `coredns` depende do node group (precisa de nós para ficar `ACTIVE`).
- O managed node group recebe automaticamente o **cluster security group** do EKS; o módulo expõe `cluster_security_group_id` (`vpc_config[0].cluster_security_group_id`) para o RDS.
- *Alternativa*: `CONFIG_MAP`/`aws-auth` — descartada, é o modelo legado.
- *Alternativa*: versão fixa como padrão — descartada pelo usuário; a fixação continua possível via variável.

### D7. RDS PostgreSQL
- `aws_db_subnet_group` com as duas subnets de banco.
- Security Group próprio na VPC: ingress TCP 5432 **apenas** de `cluster_security_group_id` (referência a SG, não CIDR); egress padrão.
- `aws_db_instance`: `engine = "postgres"`, `engine_version = var.db_engine_version` (padrão `"18"`, a AWS escolhe a minor mais recente), `auto_minor_version_upgrade = true`, `instance_class = var.db_instance_class` (padrão `db.t4g.micro`), `allocated_storage = var.db_allocated_storage` (padrão 20), `storage_type = "gp3"`, `storage_encrypted = true`, `multi_az = var.db_multi_az` (padrão `true`), `publicly_accessible = false`, `db_name = var.db_name` (padrão `kubedevnews`), `username = var.db_username` (padrão `kubedevnews`), `password = var.db_password`, `backup_retention_period = 7`, `skip_final_snapshot = var.db_skip_final_snapshot` (padrão `true`), `deletion_protection = var.db_deletion_protection` (padrão `false`), `apply_immediately = true`.
- Parameter group padrão do RDS (mantém `rds.force_ssl = 1`, compatível com `DB_SSL_REQUIRE=true`).
- Os padrões de snapshot/proteção favorecem um ambiente de estudo destruível; produção deve inverter as duas flags.

### D8. Credenciais do banco por variáveis
- `var.db_username` (padrão `kubedevnews`) e `var.db_password` (`sensitive = true`, **sem padrão**, obrigatória).
- `validation` na senha: 8 a 128 caracteres e sem `/`, `@`, `"` ou espaço (caracteres rejeitados pelo RDS), detectando o erro no `plan` e não depois de minutos de `apply`.
- A senha não é exposta em nenhum output. A pipeline usa `TF_VAR_db_password` vindo do seu próprio store de secrets; localmente, `terraform.tfvars` (no `.gitignore`).
- *Alternativa*: `manage_master_user_password` (Secrets Manager) — descartada pelo usuário.
- *Alternativa*: `random_password` — descartada; a pipeline precisaria ler a senha do state/output.

### D9. Outputs do root
`region`, `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `database_subnet_ids`, `cluster_name`, `cluster_endpoint`, `cluster_version`, `kubeconfig_command` (`aws eks update-kubeconfig --region <r> --name <c>`), `rds_endpoint` (address, sem porta), `rds_port`, `db_name`, `db_username`. Nenhum output sensível.

### D10. Validação estática
Executada em `terraform/`:
1. `terraform fmt -recursive` — formata root e módulos.
2. `terraform fmt -recursive -check` — deve sair com código 0.
3. `terraform init -backend=false` — baixa o provider sem acessar o S3 nem exigir credenciais.
4. `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` — completa o lock file.
5. `terraform validate` — deve reportar `Success! The configuration is valid.`

O `validate` checa sintaxe, tipos, referências entre módulos, argumentos do provider e blocos `validation` com valores estáticos; não consulta data sources, então não chama a AWS. `plan` e `apply` não fazem parte desta change.

### D11. `.gitignore` e documentação
`.gitignore` ganha: `**/.terraform/`, `*.tfstate`, `*.tfstate.*`, `crash.log`, `terraform/terraform.tfvars`, `terraform/backend.hcl`, `*.tfplan`. O `.terraform.lock.hcl` **não** é ignorado. `terraform/README.md` documenta: pré-requisitos, criação do bucket, `backend.hcl`, variáveis (com destaque para `db_password` e flags de custo), `init`/`plan`/`apply`, outputs para a pipeline, comportamento de upgrade automático da versão do Kubernetes, validação e `destroy`.

## Risks / Trade-offs

- **[Upgrade automático do Kubernetes]** Com `kubernetes_version = null`, quando a AWS lançar uma nova versão, o próximo `plan` propõe upgrade do control plane, mesmo que o apply seja por outro motivo. Se o cluster estiver duas versões atrás, o apply falha (o EKS sobe uma minor por vez). → Documentar no README; fixar a versão via `tfvars` quando estabilidade for necessária; sempre revisar o `plan`.
- **[Senha no state]** Com credenciais por variável, a senha fica em texto puro no state. → Backend com `encrypt = true`, bucket privado com versionamento e acesso restrito; nenhum output expõe a senha.
- **[Custo]** EKS (~US$ 73/mês), 2 NAT Gateways (~US$ 65/mês + tráfego), RDS Multi-AZ (2× a instância) e 2 nós `t3.medium`. → Flags `single_nat_gateway` e `db_multi_az`; README com custos aproximados e `terraform destroy`.
- **[Validação só estática]** `validate` não detecta erros de runtime da AWS (cotas, combinações de instância/versão indisponíveis, nome de bucket, permissões). → Valores padrão verificados contra a AWS em 28/10/2026 (EKS 1.37, PG 18.6 em `db.t4g.micro` Multi-AZ); `plan` real fica para a pipeline.
- **[Endpoint público do EKS aberto]** `public_access_cidrs` padrão `0.0.0.0/0` (autenticado por IAM). → Variável permite restringir ao IP da pipeline/escritório.
- **[Maior versão por `STANDARD_SUPPORT`]** A lógica assume major `1` no formato `1.N`. → Aceitável; se o formato mudar, basta fixar `kubernetes_version`.
- **[Compatibilidade PostgreSQL 18 × dependências antigas]** `sequelize@6.19` e `pg@8.7.3` são de 2022. O protocolo e o SCRAM são os mesmos, mas não há validação em runtime nesta change. → `db_engine_version` parametrizável (ex.: `"17"`) se surgir incompatibilidade.
- **[Destroy com RDS]** `skip_final_snapshot = true` por padrão apaga os dados no `destroy`. → Intencional para estudo; flag para produção.

## Migration Plan

Não há infraestrutura anterior. Uso esperado (fora desta change):
1. Criar o bucket S3 do state e preencher `terraform/backend.hcl`.
2. `terraform init -backend-config=backend.hcl`.
3. Definir `TF_VAR_db_password` (e opcionais em `terraform.tfvars`).
4. `terraform plan` → `terraform apply`.
5. A pipeline usa os outputs para `aws eks update-kubeconfig` e para preencher ConfigMap/Secret.

Rollback: `terraform destroy` (remove tudo, incluindo os dados do RDS com os padrões atuais). Os Services `LoadBalancer` devem ser removidos do cluster antes do `destroy`, senão os ELBs criados pelo Kubernetes seguram ENIs e impedem a deleção da VPC.

## Open Questions

Nenhuma no momento.
