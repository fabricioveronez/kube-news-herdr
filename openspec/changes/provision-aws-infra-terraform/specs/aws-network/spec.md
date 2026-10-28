## ADDED Requirements

### Requirement: VPC própria e independente
O módulo `network` MUST criar uma VPC dedicada com CIDR `var.vpc_cidr` (padrão `10.0.0.0/16`), com `enable_dns_support` e `enable_dns_hostnames` habilitados. Nenhum recurso MUST depender de VPC ou subnet pré-existente (incluindo a VPC default).

#### Scenario: DNS habilitado
- **WHEN** o recurso `aws_vpc` é inspecionado
- **THEN** `enable_dns_support` e `enable_dns_hostnames` são `true`

#### Scenario: Sem dependência da VPC default
- **WHEN** o código é inspecionado
- **THEN** não há `data "aws_vpc"` nem `data "aws_subnet"` com `default = true` ou IDs fixos

### Requirement: Duas zonas de disponibilidade
O módulo MUST usar exatamente duas AZs, obtidas dinamicamente de `data "aws_availability_zones"` com `state = "available"` na região configurada, sem nomes de AZ fixos no código.

#### Scenario: AZs dinâmicas
- **WHEN** a região é alterada
- **THEN** as subnets são criadas nas duas primeiras AZs disponíveis da nova região sem alteração de código

### Requirement: Três camadas de subnets por AZ
O módulo MUST criar, em cada uma das duas AZs, uma subnet pública, uma privada e uma de banco (seis subnets no total), com CIDRs `/24` derivados de `var.vpc_cidr` via `cidrsubnet`. Subnets públicas MUST ter `map_public_ip_on_launch = true`; privadas e de banco MUST NOT atribuir IP público.

#### Scenario: Seis subnets distribuídas
- **WHEN** as subnets do módulo são inspecionadas
- **THEN** existem duas públicas, duas privadas e duas de banco, uma de cada camada em cada AZ

#### Scenario: CIDRs derivados
- **WHEN** `vpc_cidr` é alterado
- **THEN** os CIDRs das subnets são recalculados sem alteração de código

### Requirement: Roteamento e saída para a internet
O módulo MUST criar um Internet Gateway com rota padrão das subnets públicas. Subnets privadas MUST ter rota padrão para um NAT Gateway. Subnets de banco MUST NOT ter rota para a internet (nem IGW nem NAT).

#### Scenario: Banco isolado
- **WHEN** a route table das subnets de banco é inspecionada
- **THEN** ela não contém rota `0.0.0.0/0`

#### Scenario: Privadas com saída via NAT
- **WHEN** as route tables das subnets privadas são inspecionadas
- **THEN** cada uma tem rota `0.0.0.0/0` apontando para um NAT Gateway

### Requirement: NAT Gateway com alta disponibilidade configurável
Com `var.single_nat_gateway = false` (padrão), o módulo MUST criar um NAT Gateway com Elastic IP em cada subnet pública, e cada subnet privada MUST rotear para o NAT da sua própria AZ. Com `single_nat_gateway = true`, MUST criar um único NAT Gateway na primeira AZ, usado por ambas as subnets privadas.

#### Scenario: Padrão com NAT por AZ
- **WHEN** o módulo é usado com valores padrão
- **THEN** existem dois NAT Gateways e a subnet privada de cada AZ usa o NAT da mesma AZ

#### Scenario: NAT único para economia
- **WHEN** `single_nat_gateway = true`
- **THEN** existe um único NAT Gateway e as duas subnets privadas roteiam para ele

### Requirement: Tags de descoberta de load balancer
Subnets públicas MUST ter a tag `kubernetes.io/role/elb = "1"` e subnets privadas MUST ter `kubernetes.io/role/internal-elb = "1"`, para que Services `type: LoadBalancer` no EKS encontrem as subnets.

#### Scenario: Subnets públicas elegíveis para LB externo
- **WHEN** as tags das subnets públicas são inspecionadas
- **THEN** ambas contêm `kubernetes.io/role/elb = "1"`

### Requirement: Outputs do módulo de rede
O módulo MUST expor `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `database_subnet_ids` e `azs`.

#### Scenario: Consumo pelos outros módulos
- **WHEN** o root module é inspecionado
- **THEN** o módulo `eks` recebe `private_subnet_ids` e o módulo `rds` recebe `vpc_id` e `database_subnet_ids` a partir dos outputs de `network`
