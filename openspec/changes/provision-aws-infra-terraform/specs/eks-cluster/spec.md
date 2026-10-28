## ADDED Requirements

### Requirement: Versão mais recente do Kubernetes por padrão
O módulo `eks` MUST aceitar `kubernetes_version` (padrão `null`). Quando `null`, a versão do cluster MUST ser a maior versão em `STANDARD_SUPPORT` retornada por `data "aws_eks_cluster_versions"`, comparada numericamente pelo componente minor. Quando informada, a versão da variável MUST prevalecer.

#### Scenario: Versão dinâmica
- **WHEN** `kubernetes_version` não é informada e a AWS oferece `1.34`, `1.35`, `1.36` e `1.37` em suporte padrão
- **THEN** o cluster é configurado com a versão `1.37`

#### Scenario: Comparação numérica
- **WHEN** a lógica de seleção é inspecionada
- **THEN** ela compara o minor como número, não por ordenação de string

#### Scenario: Versão fixada
- **WHEN** `kubernetes_version = "1.36"` é informada
- **THEN** o cluster usa `1.36` independentemente das versões disponíveis

### Requirement: IAM do cluster e dos nós
O módulo MUST criar uma role para o cluster (principal `eks.amazonaws.com`) com `AmazonEKSClusterPolicy` e uma role para os nós (principal `ec2.amazonaws.com`) com `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` e `AmazonEC2ContainerRegistryReadOnly`. O cluster e o node group MUST depender explicitamente dos respectivos attachments.

#### Scenario: Ordem de criação e deleção
- **WHEN** `aws_eks_cluster` e `aws_eks_node_group` são inspecionados
- **THEN** ambos têm `depends_on` para os `aws_iam_role_policy_attachment` das suas roles

### Requirement: Cluster nas subnets privadas com endpoint público e privado
O cluster MUST usar as subnets privadas das duas AZs, com `endpoint_private_access = true`, `endpoint_public_access = true` e `public_access_cidrs = var.cluster_public_access_cidrs` (padrão `["0.0.0.0/0"]`).

#### Scenario: Acesso do kubectl externo
- **WHEN** o `vpc_config` do cluster é inspecionado
- **THEN** os acessos privado e público estão habilitados e os CIDRs públicos vêm da variável

### Requirement: Autenticação por access entries
O cluster MUST usar `authentication_mode = "API"` e `bootstrap_cluster_creator_admin_permissions = true`. Para cada ARN em `var.cluster_admin_principal_arns` (padrão `[]`), o módulo MUST criar um `aws_eks_access_entry` e uma `aws_eks_access_policy_association` com `AmazonEKSClusterAdminPolicy` em escopo `cluster`.

#### Scenario: Sem aws-auth
- **WHEN** o `access_config` é inspecionado
- **THEN** `authentication_mode` é `"API"` e o código não gerencia o ConfigMap `aws-auth`

#### Scenario: Admin adicional para a pipeline
- **WHEN** `cluster_admin_principal_arns` contém o ARN de uma role
- **THEN** são criados uma access entry e uma associação de `AmazonEKSClusterAdminPolicy` para essa role

### Requirement: Managed node group nas duas AZs
O módulo MUST criar um managed node group nas subnets privadas das duas AZs, com `ami_type = "AL2023_x86_64_STANDARD"`, `capacity_type = "ON_DEMAND"`, `instance_types = var.node_instance_types` (padrão `["t3.medium"]`) e escala `desired/min/max` padrão `2/2/4`. O `desired_size` MUST estar em `ignore_changes`.

#### Scenario: Nós distribuídos
- **WHEN** o node group é inspecionado
- **THEN** ele usa as duas subnets privadas e `min_size` é pelo menos 2

### Requirement: Addons gerenciados na versão compatível mais recente
O módulo MUST instalar `vpc-cni`, `kube-proxy` e `coredns` como `aws_eks_addon`, cada um com `addon_version` vinda de `data "aws_eks_addon_version"` com `most_recent = true` para a versão do cluster. O `coredns` MUST depender do node group.

#### Scenario: Versões de addon dinâmicas
- **WHEN** a versão do cluster muda
- **THEN** as versões dos addons são resolvidas novamente para a versão compatível mais recente

### Requirement: Outputs do módulo EKS
O módulo MUST expor `cluster_name`, `cluster_endpoint`, `cluster_version`, `cluster_security_group_id` (security group gerenciado pelo EKS, anexado aos nós) e `node_role_arn`.

#### Scenario: SG do cluster para o RDS
- **WHEN** o root module é inspecionado
- **THEN** o módulo `rds` recebe `cluster_security_group_id` do módulo `eks`
