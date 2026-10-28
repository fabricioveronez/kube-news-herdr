## ADDED Requirements

### Requirement: Dockerfile em src com contexto de build próprio
O projeto MUST ter um `Dockerfile` em `src/` que construa a imagem da aplicação usando `src/` como contexto de build, em estágio único (sem multi-stage) e sem `tini` ou outro init.

#### Scenario: Build a partir da raiz do projeto
- **WHEN** `docker build -t kube-news ./src` é executado na raiz do projeto
- **THEN** o build conclui com sucesso e gera a imagem `kube-news`

#### Scenario: Estágio único
- **WHEN** o `src/Dockerfile` é inspecionado
- **THEN** ele contém exatamente uma instrução `FROM` e nenhuma referência a `tini`

### Requirement: Dependências instaladas a partir do lockfile
A imagem MUST instalar as dependências com `npm ci --omit=dev` a partir do `package-lock.json`, em camada anterior à cópia do código, sem alterar versões das dependências.

#### Scenario: Cache de dependências
- **WHEN** apenas um arquivo de código (ex.: `src/server.js`) é alterado e a imagem é reconstruída
- **THEN** a camada de `npm ci` é reaproveitada do cache

#### Scenario: Versões preservadas
- **WHEN** a imagem é construída
- **THEN** `src/package.json` e `src/package-lock.json` permanecem inalterados no repositório

### Requirement: Diretório de trabalho compatível com a aplicação
O conteúdo de `src/` MUST ser copiado para o diretório de trabalho da imagem, de forma que `static/` e `views/` sejam resolvidos relativos ao diretório onde `node server.js` é executado.

#### Scenario: Arquivos estáticos e views servidos
- **WHEN** o container está em execução e recebe `GET /` e `GET /styles/main.css`
- **THEN** ambas as requisições retornam HTTP 200

### Requirement: Execução como usuário não-root numérico
A imagem MUST definir o usuário de execução pelo UID numérico `1000`, expor a porta `8080` e iniciar a aplicação com `CMD ["node", "server.js"]` em forma exec.

#### Scenario: Usuário do processo
- **WHEN** `docker run --rm --entrypoint id kube-news -u` é executado
- **THEN** a saída é `1000`

#### Scenario: Porta exposta
- **WHEN** a configuração da imagem é inspecionada com `docker image inspect`
- **THEN** `ExposedPorts` contém `8080/tcp`

### Requirement: Contexto de build limpo
O projeto MUST ter um `src/.dockerignore` que exclua no mínimo `node_modules`, logs do npm (`npm-debug.log*`), arquivos `.env*`, o próprio `Dockerfile` e o `.dockerignore`.

#### Scenario: node_modules local não entra na imagem
- **WHEN** existe um `src/node_modules` local e a imagem é construída
- **THEN** o `node_modules` dentro da imagem é o gerado pelo `npm ci`, não o do host
