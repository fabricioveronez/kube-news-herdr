## ADDED Requirements

### Requirement: Projeto Terraform em pasta própria com módulos locais
O projeto Terraform MUST ficar em `terraform/` (minúsculo) na raiz do repositório, com um root module que compõe os módulos locais `terraform/modules/network`, `terraform/modules/eks` e `terraform/modules/rds`. Nenhum bloco `module` MUST referenciar fonte externa (Terraform Registry, Git ou HTTP); todas as fontes MUST ser caminhos locais.

#### Scenario: Somente módulos locais
- **WHEN** todos os blocos `module` em `terraform/` são inspecionados
- **THEN** cada `source` começa com `./modules/` e não há referência a registry, Git ou URL

#### Scenario: Pasta com nome minúsculo
- **WHEN** a raiz do repositório é listada
- **THEN** existe o diretório `terraform/` e não existe `Terraform/`

### Requirement: Versões de Terraform e provider fixadas
O root MUST declarar `required_version = ">= 1.11"` e o provider `hashicorp/aws` com restrição `~> 6.70`. O arquivo `terraform/.terraform.lock.hcl` MUST ser versionado e conter hashes para as plataformas `linux_amd64`, `darwin_arm64` e `darwin_amd64`.

#### Scenario: Provider na versão mais recente
- **WHEN** `terraform/versions.tf` é inspecionado
- **THEN** o provider `hashicorp/aws` usa a restrição `~> 6.70`

#### Scenario: Lock file multiplataforma
- **WHEN** `terraform/.terraform.lock.hcl` é inspecionado
- **THEN** ele contém o provider `registry.terraform.io/hashicorp/aws` com hashes das três plataformas

### Requirement: Região parametrizável com padrão Virgínia do Norte
O provider AWS MUST usar `var.region`, cujo valor padrão MUST ser `us-east-1`. O provider MUST aplicar `default_tags` com `Project` e `ManagedBy = "terraform"`.

#### Scenario: Região padrão
- **WHEN** nenhuma região é informada
- **THEN** o provider é configurado para `us-east-1`

#### Scenario: Região customizada
- **WHEN** `region = "sa-east-1"` é informado via variável
- **THEN** todos os recursos e data sources usam `sa-east-1`

### Requirement: State remoto em S3 com lock nativo
O root MUST declarar `backend "s3"` com `key`, `use_lockfile = true` e `encrypt = true`, sem `bucket` nem `region` fixos e sem `dynamodb_table`. MUST existir `terraform/backend.hcl.example` com `bucket` e `region` de exemplo; o `backend.hcl` real MUST estar no `.gitignore`.

#### Scenario: Lock sem DynamoDB
- **WHEN** `terraform/backend.tf` é inspecionado
- **THEN** ele contém `use_lockfile = true` e não contém `dynamodb_table`

#### Scenario: Bucket fora do código versionado
- **WHEN** o repositório é inspecionado
- **THEN** o nome real do bucket não aparece em nenhum arquivo versionado e `terraform/backend.hcl` é ignorado pelo Git

### Requirement: Outputs para a pipeline de deploy
O root MUST expor os outputs `region`, `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `database_subnet_ids`, `cluster_name`, `cluster_endpoint`, `cluster_version`, `kubeconfig_command`, `rds_endpoint`, `rds_port`, `db_name` e `db_username`. Nenhum output MUST expor a senha do banco.

#### Scenario: Senha não exposta
- **WHEN** `terraform/outputs.tf` e os outputs dos módulos são inspecionados
- **THEN** nenhum output referencia `db_password`

#### Scenario: Comando de kubeconfig pronto
- **WHEN** o output `kubeconfig_command` é inspecionado
- **THEN** ele tem o formato `aws eks update-kubeconfig --region <region> --name <cluster_name>`

### Requirement: Arquivos sensíveis e de estado fora do Git
O `.gitignore` MUST ignorar `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfplan`, `crash.log`, `terraform/terraform.tfvars` e `terraform/backend.hcl`, e MUST NOT ignorar `.terraform.lock.hcl`. MUST existir `terraform/terraform.tfvars.example` sem senha real.

#### Scenario: tfvars real ignorado
- **WHEN** `git check-ignore terraform/terraform.tfvars` é executado
- **THEN** o arquivo é reportado como ignorado

#### Scenario: Lock file versionável
- **WHEN** `git check-ignore terraform/.terraform.lock.hcl` é executado
- **THEN** o arquivo não é reportado como ignorado

### Requirement: Documentação de uso
`terraform/README.md` MUST documentar: pré-requisitos, criação do bucket do state, preenchimento do `backend.hcl`, variáveis (incluindo `db_password` obrigatória e as flags de custo), `init`/`plan`/`apply`/`destroy`, outputs para a pipeline, o comportamento de upgrade automático da versão do Kubernetes e os passos de validação.

#### Scenario: Aviso de upgrade automático
- **WHEN** o README é lido
- **THEN** ele explica que `kubernetes_version = null` acompanha a versão mais recente e como fixá-la

### Requirement: Validação estática com fmt e validate
O projeto MUST ser validado, a partir de `terraform/`, com `terraform fmt -recursive`, `terraform fmt -recursive -check`, `terraform init -backend=false` e `terraform validate`. A validação MUST NOT executar `terraform plan` nem `terraform apply` e MUST NOT exigir credenciais AWS.

#### Scenario: Formatação conforme
- **WHEN** `terraform fmt -recursive -check` é executado após a formatação
- **THEN** o comando termina com código 0 sem listar arquivos

#### Scenario: Configuração válida
- **WHEN** `terraform init -backend=false` seguido de `terraform validate` é executado
- **THEN** o `validate` termina com código 0 e reporta `Success! The configuration is valid.`

#### Scenario: Sem acesso ao backend
- **WHEN** a validação é executada sem `backend.hcl` e sem credenciais AWS
- **THEN** nenhum passo falha por falta de bucket ou credencial
