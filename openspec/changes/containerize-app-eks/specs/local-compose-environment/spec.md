## ADDED Requirements

### Requirement: Compose na raiz com aplicação e banco
O projeto MUST ter um `docker-compose.yml` na raiz com dois serviços: `app`, construído a partir de `./src`, e `postgres`, usando `postgres:16-alpine`. Um único `docker compose up` MUST subir o ambiente completo.

#### Scenario: Subida do ambiente
- **WHEN** `docker compose up -d --build` é executado na raiz do projeto
- **THEN** os serviços `app` e `postgres` ficam em execução e a aplicação responde em `http://localhost:8080`

### Requirement: Banco efêmero sem volume
O serviço `postgres` MUST NOT declarar volumes, e a porta do banco MUST NOT ser publicada no host. As credenciais do banco MUST coincidir com as variáveis passadas à aplicação.

#### Scenario: Dados não persistem entre execuções
- **WHEN** um post é criado, o ambiente é derrubado com `docker compose down` e subido novamente
- **THEN** `GET /` exibe o estado vazio ("Ainda não temos nenhum post")

#### Scenario: Nenhum volume declarado
- **WHEN** `docker compose config` é executado
- **THEN** nenhum serviço possui a chave `volumes`

### Requirement: Aplicação aguarda o banco ficar saudável
O serviço `postgres` MUST ter healthcheck com `pg_isready`, e o serviço `app` MUST depender dele com `condition: service_healthy`.

#### Scenario: Subida sem corrida
- **WHEN** o ambiente é iniciado do zero
- **THEN** o container `app` só inicia após o `postgres` estar saudável e não reinicia nem encerra por falha de conexão

### Requirement: Configuração explícita por variáveis de ambiente
O serviço `app` MUST receber `DB_HOST=postgres`, `DB_PORT=5432`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` e `DB_SSL_REQUIRE=false` explicitamente, e MUST publicar a porta `8080:8080`.

#### Scenario: Conexão sem SSL ao banco local
- **WHEN** a aplicação inicia no Compose
- **THEN** ela conecta ao serviço `postgres` sem SSL e cria a tabela de posts

### Requirement: Smoke tests do ambiente local
A validação do ambiente local MUST executar o Compose de verdade e verificar, contra `http://localhost:8080`, todos os cenários abaixo.

#### Scenario: Endpoints de saúde e métricas
- **WHEN** `GET /health`, `GET /ready` e `GET /metrics` são chamados
- **THEN** todos retornam HTTP 200, `/health` contém `"state":"up"` e `/metrics` contém `http_requests_total`

#### Scenario: Inserção em massa via API
- **WHEN** o payload de `popula-dados.http` é enviado em `POST /api/post`
- **THEN** a resposta é HTTP 200 e `GET /` passa a conter "Kubernetes na Nuvem"

#### Scenario: Criação via formulário
- **WHEN** `POST /post` é enviado com `title`, `resumo` e `description` dentro dos limites de tamanho
- **THEN** a resposta é um redirecionamento para `/` e o novo título aparece em `GET /`

#### Scenario: Visualização de post
- **WHEN** `GET /post/1` é chamado após a inserção
- **THEN** a resposta é HTTP 200 com o conteúdo do post

### Requirement: Arquivo de dados de exemplo aponta para a porta correta
O `popula-dados.http` MUST apontar para `http://localhost:8080/api/post`.

#### Scenario: Porta do arquivo de exemplo
- **WHEN** o `popula-dados.http` é inspecionado
- **THEN** a URL usa a porta `8080` e não a `4503`
