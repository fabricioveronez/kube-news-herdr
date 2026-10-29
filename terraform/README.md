# Infraestrutura AWS do Kube-News

Este root Terraform provisiona VPC, EKS e RDS PostgreSQL em `us-east-1` por padrão. Os módulos são locais; a execução desta change foi somente estática, sem criar recursos AWS.

## Arquitetura

```text
                         Internet
                            │
                        Internet Gateway
                            │
          ┌─────────────────┴─────────────────┐
          │ AZ 1                              │ AZ 2
          │ public /24 ─ NAT 1                │ public /24 ─ NAT 2
          │ private /24 ─ EKS nodes           │ private /24 ─ EKS nodes
          │ database /24 ─ RDS primary/standby│ database /24 ─ RDS standby/primary
          └─────────────────┬─────────────────┘
                            │
                     VPC 10.0.0.0/16

network ── VPC + private subnets ──▶ eks ── cluster security group ──▶ rds
       └── database subnets + VPC ───────────────────────────────────▶ rds
```

Cada AZ tem uma subnet pública, privada e de banco. As públicas saem pelo Internet Gateway; as privadas usam NAT da própria AZ por padrão. As subnets do banco não têm rota para a internet. O EKS tem endpoint privado e público; o acesso público deve ser limitado com `cluster_public_access_cidrs` quando possível. O security group do RDS aceita TCP 5432 apenas do security group do cluster.

## Pré-requisitos e state

- Terraform >= 1.11, AWS CLI e credenciais AWS com permissões para VPC, EKS, IAM, EC2, RDS e S3.
- Bucket S3 privado, globalmente único, para o state. Crie-o antes de `terraform init`. O bucket fica fora deste root para que o state não dependa de si mesmo.
- Para a validação estática, credenciais AWS e bucket não são necessários.

Exemplo para `us-east-1` (substitua o nome do bucket; use outra região com a configuração de localização exigida pela AWS):

```bash
STATE_BUCKET="meu-bucket-unico-kube-news-state"
aws s3api create-bucket --bucket "$STATE_BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$STATE_BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Restrinja o acesso ao bucket por IAM. O state contém a senha do banco em texto legível para quem puder ler o objeto, mesmo com o output oculto. Versionamento ajuda a recuperar alterações acidentais. O backend usa lock nativo em S3 (`use_lockfile = true`) e criptografia em trânsito/repouso do objeto (`encrypt = true`).

Copie `backend.hcl.example` para `backend.hcl` e defina `bucket` e `region`. O arquivo real é ignorado pelo Git. A região do backend pode diferir da região dos recursos (`var.region`).

## Variáveis

Copie `terraform.tfvars.example` para `terraform.tfvars` para ajustar valores opcionais. Esse arquivo também é ignorado pelo Git. A senha é obrigatória, sensível e deve ter 8–128 caracteres, sem `/`, `@`, aspas duplas ou espaço. Por exemplo, forneça-a por `TF_VAR_db_password` a partir do gerenciador de secrets da pipeline. Evite colocá-la no histórico do shell.

| Variável | Padrão | Uso |
|---|---|---|
| `region` | `us-east-1` | Região dos recursos |
| `project_name` | `kube-news` | Prefixo de nomes e tag Project |
| `vpc_cidr` | `10.0.0.0/16` | Seis subnets `/24` derivadas deste bloco |
| `single_nat_gateway` | `false` | `true` reduz custo, com perda de redundância de saída |
| `kubernetes_version` | `null` | Versão EKS dinâmica ou minor fixada |
| `cluster_public_access_cidrs` | `["0.0.0.0/0"]` | CIDRs autorizados no endpoint público (IAM ainda é exigido) |
| `cluster_admin_principal_arns` | `[]` | Roles/usuários IAM adicionais com administração do cluster |
| `node_instance_types` | `["t3.medium"]` | Tipos dos nós |
| `node_desired_size`, `node_min_size`, `node_max_size` | `2`, `2`, `4` | Escala do node group |
| `db_engine_version` | `18` | Major PostgreSQL |
| `db_instance_class` | `db.t4g.micro` | Classe RDS |
| `db_allocated_storage` | `20` | GiB gp3 |
| `db_multi_az` | `true` | `false` reduz custo, com perda de standby |
| `db_name`, `db_username` | `kubedevnews` | Banco inicial e usuário master |
| `db_password` | obrigatório | Senha master; use `TF_VAR_db_password` |
| `db_skip_final_snapshot` | `true` | `false` cria snapshot final no destroy |
| `db_deletion_protection` | `false` | `true` impede remoção acidental |

Com `kubernetes_version = null`, cada novo `plan` consulta as versões EKS em suporte padrão e pode propor upgrade do control plane quando a AWS lançar uma nova versão. Revise o plano; o EKS pode exigir upgrades de uma minor por vez. Para estabilidade, fixe por exemplo `kubernetes_version = "1.37"` em `terraform.tfvars` e avance a versão deliberadamente.

## Custos aproximados

Exemplo de 730 horas/mês, sem impostos, tráfego, storage e outros extras: EKS em suporte padrão fica em torno de **US$ 73/mês**; dois NAT Gateways, cerca de **US$ 66/mês** mais processamento de dados; dois nós `t3.medium`, cerca de **US$ 61/mês**. O RDS Multi-AZ, storage gp3, EBS dos nós, Elastic IPs, load balancers e transferência de dados são adicionais. Assim, o padrão já passa de **US$ 200/mês antes do RDS e desses extras**. Valores variam por região e data; calcule seu caso na [AWS Pricing Calculator](https://calculator.aws/). `single_nat_gateway = true` e `db_multi_az = false` reduzem custo e disponibilidade. Consulte as tabelas oficiais de [EKS](https://aws.amazon.com/eks/pricing/), [VPC/NAT](https://aws.amazon.com/vpc/pricing/), [EC2](https://aws.amazon.com/ec2/instance-types/t3/) e [RDS](https://aws.amazon.com/rds/postgresql/pricing/).

## Operação

Os comandos abaixo são para uso posterior, após configurar credenciais, backend e senha. Eles **não foram executados** na implementação desta change.

```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Na pipeline, leia `cluster_name`, `cluster_endpoint`, `region` e `kubeconfig_command` para acessar o EKS. Use `rds_endpoint`, `rds_port`, `db_name` e `db_username` para preencher `DB_HOST`, `DB_PORT`, `DB_DATABASE` e `DB_USERNAME`; forneça `DB_PASSWORD` de um secret da pipeline/Kubernetes, nunca de um output Terraform. Configure `DB_SSL_REQUIRE=true` na aplicação.

Para remover a infraestrutura, remova primeiro os Services Kubernetes `type: LoadBalancer` e aguarde a exclusão dos ELBs e ENIs. Depois execute `terraform destroy` com o mesmo backend e as variáveis necessárias. Com os padrões, o RDS é removido **sem snapshot final**. Para preservar dados, configure `db_skip_final_snapshot = false` e `db_deletion_protection = true` antes do uso; desative a proteção deliberadamente quando for destruir.

## Validação estática

Em `terraform/`, sem credenciais AWS ou acesso ao bucket:

```bash
terraform fmt -recursive
terraform fmt -recursive -check
terraform init -backend=false
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
terraform validate
```

O lock file `.terraform.lock.hcl` é versionado. Esta validação não executa `plan` nem `apply` e não detecta erros de permissão, cota ou disponibilidade de recursos na conta AWS.
