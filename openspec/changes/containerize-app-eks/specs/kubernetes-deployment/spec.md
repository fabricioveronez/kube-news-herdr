## ADDED Requirements

### Requirement: Manifestos de deploy em k8s sem namespace
O projeto MUST ter, em `k8s/`, os manifestos `configmap.yaml`, `secret.yaml`, `deployment.yaml` e `service.yaml`. Nenhum manifesto MUST definir `kind: Namespace` nem `metadata.namespace`. Os manifestos cobrem apenas o deploy da aplicação, sem Ingress, HPA ou PodDisruptionBudget.

#### Scenario: Namespace definido por quem aplica
- **WHEN** os arquivos em `k8s/` são inspecionados
- **THEN** nenhum contém `kind: Namespace` nem `namespace:` em `metadata`

### Requirement: Configuração do RDS via ConfigMap e Secret
O ConfigMap `kube-news-config` MUST conter `DB_HOST` (placeholder do endpoint RDS), `DB_PORT`, `DB_DATABASE` e `DB_SSL_REQUIRE: "true"`. O Secret comum `kube-news-db` (tipo `Opaque`) MUST conter `DB_USERNAME` e `DB_PASSWORD` com valores placeholder, sem credenciais reais.

#### Scenario: SSL habilitado para o RDS
- **WHEN** o ConfigMap é inspecionado
- **THEN** `DB_SSL_REQUIRE` tem valor `"true"`

#### Scenario: Sem credenciais reais versionadas
- **WHEN** o `k8s/secret.yaml` é inspecionado
- **THEN** `DB_USERNAME` e `DB_PASSWORD` contêm placeholders evidentes

### Requirement: Deployment da aplicação
O Deployment `kube-news` MUST ter 2 réplicas, imagem com tag explícita (nunca `latest`) no formato de repositório ECR, `envFrom` referenciando o ConfigMap e o Secret, `containerPort: 8080`, `livenessProbe` HTTP em `/health`, `readinessProbe` HTTP em `/ready`, e `resources` com requests e limits de CPU e memória.

#### Scenario: Probes mapeadas aos endpoints da aplicação
- **WHEN** o Deployment é inspecionado
- **THEN** a liveness aponta para `/health` na porta 8080 e a readiness para `/ready` na porta 8080

#### Scenario: Tag de imagem explícita
- **WHEN** a imagem do container é inspecionada
- **THEN** ela não termina em `:latest` nem omite a tag

### Requirement: Contexto de segurança não-root
O pod MUST declarar `runAsNonRoot: true` e `runAsUser: 1000`, e o container MUST declarar `allowPrivilegeEscalation: false` e remover todas as capabilities (`drop: ["ALL"]`).

#### Scenario: UID numérico compatível com a imagem
- **WHEN** o securityContext é inspecionado
- **THEN** `runAsUser` é `1000`, igual ao `USER` do `src/Dockerfile`

### Requirement: Exposição via Service LoadBalancer
O Service `kube-news` MUST ser do tipo `LoadBalancer`, expor a porta `80` com `targetPort: 8080` e selecionar os pods do Deployment pelo label `app: kube-news`.

#### Scenario: Seletor alinhado ao Deployment
- **WHEN** o Service e o Deployment são inspecionados
- **THEN** o `selector` do Service corresponde aos labels do template de pod do Deployment

### Requirement: Validação com kind e dry-run de servidor
Os manifestos MUST ser validados criando um cluster `kind` local chamado `kube-news-validate` e executando `kubectl apply -f k8s/ --dry-run=server --context kind-kube-news-validate` no namespace `default`. O cluster MUST ser removido ao final.

#### Scenario: Dry-run aceito pelo API server
- **WHEN** o dry-run de servidor é executado contra o cluster `kind`
- **THEN** o comando termina com código 0 e reporta os quatro objetos como `(server dry run)`

#### Scenario: Nada é aplicado de fato
- **WHEN** a validação termina
- **THEN** nenhum objeto `kube-news` existe no namespace `default` e o cluster `kube-news-validate` foi removido
