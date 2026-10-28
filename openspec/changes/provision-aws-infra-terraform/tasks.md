## 1. Fundação do projeto

- [ ] 1.1 Adicionar ao `.gitignore` as entradas `**/.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfplan`, `crash.log`, `terraform/terraform.tfvars` e `terraform/backend.hcl` (sem ignorar `.terraform.lock.hcl`)
- [ ] 1.2 Criar `terraform/versions.tf` com `required_version = ">= 1.11"` e `hashicorp/aws` `~> 6.70`
- [ ] 1.3 Criar `terraform/backend.tf` com `backend "s3"` parcial (`key = "kube-news/terraform.tfstate"`, `use_lockfile = true`, `encrypt = true`) e `terraform/backend.hcl.example`
- [ ] 1.4 Criar `terraform/providers.tf` com `region = var.region` e `default_tags` (`Project`, `ManagedBy = "terraform"`)
- [ ] 1.5 Criar `terraform/variables.tf` do root: `region` (padrão `us-east-1`), `project_name`, `vpc_cidr`, `single_nat_gateway`, `kubernetes_version` (padrão `null`), `cluster_public_access_cidrs`, `cluster_admin_principal_arns`, `node_instance_types`, `node_desired_size/min_size/max_size`, `db_engine_version`, `db_instance_class`, `db_allocated_storage`, `db_multi_az`, `db_name`, `db_username`, `db_password` (sensível, sem padrão, com `validation`), `db_skip_final_snapshot`, `db_deletion_protection`

## 2. Módulo network

- [ ] 2.1 Criar `terraform/modules/network/` (`versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`) com `data "aws_availability_zones"` e `slice` para duas AZs
- [ ] 2.2 Criar a VPC com DNS habilitado e o Internet Gateway
- [ ] 2.3 Criar as seis subnets `/24` via `cidrsubnet` (públicas n=0/1, privadas n=10/11, banco n=20/21), com `map_public_ip_on_launch` só nas públicas e as tags `kubernetes.io/role/elb` e `kubernetes.io/role/internal-elb`
- [ ] 2.4 Criar EIPs e NAT Gateways (um por AZ, ou um só com `single_nat_gateway = true`)
- [ ] 2.5 Criar as route tables: pública (rota para o IGW), uma privada por AZ (rota para o NAT correspondente) e a de banco sem rota para a internet, com as associações
- [ ] 2.6 Expor os outputs `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `database_subnet_ids` e `azs`

## 3. Módulo eks

- [ ] 3.1 Criar `terraform/modules/eks/` (`versions.tf`, `variables.tf`, `main.tf`, `iam.tf`, `addons.tf`, `outputs.tf`)
- [ ] 3.2 Implementar a resolução de versão: `data "aws_eks_cluster_versions"` com `STANDARD_SUPPORT`, maior minor por comparação numérica e `coalesce` com `var.kubernetes_version`
- [ ] 3.3 Criar as roles IAM do cluster e dos nós com os policy attachments
- [ ] 3.4 Criar `aws_eks_cluster` nas subnets privadas com endpoint público + privado, `public_access_cidrs`, `authentication_mode = "API"`, `bootstrap_cluster_creator_admin_permissions = true` e `depends_on` nos attachments
- [ ] 3.5 Criar `aws_eks_access_entry` e `aws_eks_access_policy_association` (`AmazonEKSClusterAdminPolicy`, escopo `cluster`) para cada ARN em `cluster_admin_principal_arns`
- [ ] 3.6 Criar o managed node group (AL2023, ON_DEMAND, subnets privadas, escala 2/2/4, `ignore_changes` em `desired_size`, `depends_on` nos attachments)
- [ ] 3.7 Criar os addons `vpc-cni`, `kube-proxy` e `coredns` com `data "aws_eks_addon_version"` (`most_recent = true`), `OVERWRITE` em create/update e `coredns` dependente do node group
- [ ] 3.8 Expor os outputs `cluster_name`, `cluster_endpoint`, `cluster_version`, `cluster_security_group_id` e `node_role_arn`

## 4. Módulo rds

- [ ] 4.1 Criar `terraform/modules/rds/` (`versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`), com `db_password` sensível e o mesmo bloco `validation` do root
- [ ] 4.2 Criar o `aws_db_subnet_group` com as duas subnets de banco
- [ ] 4.3 Criar o Security Group do RDS com uma única regra de entrada TCP 5432 originada no `cluster_security_group_id`
- [ ] 4.4 Criar a `aws_db_instance` PostgreSQL (versão `18`, `db.t4g.micro`, gp3 criptografado, privada, `multi_az` por variável, credenciais por variável, backup de 7 dias, snapshot final e proteção por variável, sem Secrets Manager)
- [ ] 4.5 Expor os outputs `endpoint` (`address`), `port`, `db_name` e `username`, sem a senha

## 5. Composição do root

- [ ] 5.1 Criar `terraform/main.tf` instanciando `network`, `eks` e `rds` com `source = "./modules/..."` e ligando os outputs entre módulos
- [ ] 5.2 Criar `terraform/outputs.tf` com `region`, `vpc_id`, os IDs de subnets, `cluster_name`, `cluster_endpoint`, `cluster_version`, `kubeconfig_command`, `rds_endpoint`, `rds_port`, `db_name` e `db_username`
- [ ] 5.3 Criar `terraform/terraform.tfvars.example` com os valores padrão comentados e sem senha real
- [ ] 5.4 Conferir que nenhum `source` de módulo aponta para registry, Git ou URL e que nenhum output referencia `db_password`

## 6. Validação estática

- [ ] 6.1 Em `terraform/`, executar `terraform fmt -recursive`
- [ ] 6.2 Executar `terraform fmt -recursive -check` e confirmar código de saída 0
- [ ] 6.3 Executar `terraform init -backend=false` e confirmar o download do provider `hashicorp/aws` 6.x
- [ ] 6.4 Executar `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` e confirmar as três plataformas no `.terraform.lock.hcl`
- [ ] 6.5 Executar `terraform validate` e confirmar `Success! The configuration is valid.`
- [ ] 6.6 Confirmar com `git check-ignore` que `terraform/.terraform/`, `terraform/terraform.tfvars` e `terraform/backend.hcl` são ignorados e que `terraform/.terraform.lock.hcl` não é
- [ ] 6.7 Confirmar que nenhum `plan` ou `apply` foi executado e que não existe state local em `terraform/`

## 7. Documentação

- [ ] 7.1 Criar `terraform/README.md` com a arquitetura (diagrama de rede e módulos), pré-requisitos e criação do bucket do state (versionamento + bloqueio de acesso público)
- [ ] 7.2 Documentar `backend.hcl`, as variáveis (destaque para `db_password` via `TF_VAR_db_password` e para as flags `single_nat_gateway`/`db_multi_az`) e os custos aproximados
- [ ] 7.3 Documentar `init`/`plan`/`apply`/`destroy`, os outputs para a pipeline e o aviso de remover Services `LoadBalancer` antes do `destroy`
- [ ] 7.4 Documentar o comportamento de `kubernetes_version = null` (upgrade automático) e como fixar a versão
- [ ] 7.5 Documentar os passos de validação (`fmt`, `init -backend=false`, `validate`)
- [ ] 7.6 Adicionar ao `README.md` da raiz uma seção curta apontando para `terraform/README.md`
