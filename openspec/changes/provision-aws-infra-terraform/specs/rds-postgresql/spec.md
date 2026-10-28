## ADDED Requirements

### Requirement: Instância RDS PostgreSQL privada
O módulo `rds` MUST criar uma `aws_db_instance` com `engine = "postgres"`, `engine_version = var.db_engine_version` (padrão `"18"`), `auto_minor_version_upgrade = true`, `instance_class = var.db_instance_class` (padrão `db.t4g.micro`), `storage_type = "gp3"`, `storage_encrypted = true` e `publicly_accessible = false`. O banco inicial MUST ser `var.db_name` (padrão `kubedevnews`).

#### Scenario: Banco não exposto
- **WHEN** a instância é inspecionada
- **THEN** `publicly_accessible` é `false` e `storage_encrypted` é `true`

#### Scenario: Banco esperado pela aplicação
- **WHEN** a instância é criada com valores padrão
- **THEN** o banco `kubedevnews` existe, igual ao padrão de `DB_DATABASE` da aplicação

### Requirement: Subnets de banco em duas AZs
O módulo MUST criar um `aws_db_subnet_group` com as duas subnets de banco do módulo `network`.

#### Scenario: Subnet group multi-AZ
- **WHEN** o subnet group é inspecionado
- **THEN** ele contém duas subnets em AZs diferentes, ambas da camada de banco

### Requirement: Multi-AZ configurável
`multi_az` MUST vir de `var.db_multi_az`, com padrão `true`.

#### Scenario: Alta disponibilidade padrão
- **WHEN** o módulo é usado com valores padrão
- **THEN** a instância é criada com `multi_az = true`

#### Scenario: Modo econômico
- **WHEN** `db_multi_az = false`
- **THEN** a instância é criada em uma única AZ

### Requirement: Acesso restrito ao cluster EKS
O módulo MUST criar um Security Group na VPC do projeto, cuja única regra de entrada MUST ser TCP 5432 com origem no `cluster_security_group_id` do EKS. Nenhuma regra de entrada MUST usar bloco CIDR.

#### Scenario: Somente pods/nós do EKS acessam o banco
- **WHEN** as regras de entrada do SG do RDS são inspecionadas
- **THEN** existe apenas a porta 5432 com origem no security group do cluster

### Requirement: Credenciais por variáveis sem Secrets Manager
O usuário master MUST vir de `var.db_username` (padrão `kubedevnews`) e a senha de `var.db_password`, declarada com `sensitive = true` e sem valor padrão. `db_password` MUST ter um bloco `validation` que exija de 8 a 128 caracteres e rejeite `/`, `@`, `"` e espaço. O módulo MUST NOT usar `manage_master_user_password` nem Secrets Manager.

#### Scenario: Senha obrigatória
- **WHEN** o Terraform é executado sem informar `db_password`
- **THEN** a execução pede ou exige o valor, sem usar padrão

#### Scenario: Senha inválida rejeitada cedo
- **WHEN** `db_password` contém `@` ou tem menos de 8 caracteres
- **THEN** a validação da variável falha antes de qualquer chamada à AWS

#### Scenario: Sem Secrets Manager
- **WHEN** o módulo é inspecionado
- **THEN** não há `manage_master_user_password` nem recursos `aws_secretsmanager_*`

### Requirement: Comportamento de destroy configurável
`skip_final_snapshot` MUST vir de `var.db_skip_final_snapshot` (padrão `true`) e `deletion_protection` de `var.db_deletion_protection` (padrão `false`). `backup_retention_period` MUST ser maior que zero.

#### Scenario: Ambiente de estudo destruível
- **WHEN** `terraform destroy` é executado com valores padrão
- **THEN** a instância pode ser removida sem snapshot final e sem bloqueio de proteção

### Requirement: SSL compatível com a aplicação
O módulo MUST usar o parameter group padrão do PostgreSQL (com `rds.force_ssl` ativo), compatível com a aplicação configurada com `DB_SSL_REQUIRE=true`.

#### Scenario: SSL não desabilitado
- **WHEN** o módulo é inspecionado
- **THEN** não há parameter group que defina `rds.force_ssl = 0`

### Requirement: Outputs do módulo RDS
O módulo MUST expor `endpoint` (somente host, sem porta), `port`, `db_name` e `username`, e MUST NOT expor a senha.

#### Scenario: Host pronto para DB_HOST
- **WHEN** o output `endpoint` é inspecionado
- **THEN** ele referencia o atributo `address` da instância, sem `:5432`
