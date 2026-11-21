# Modelo de domínio e responsabilidades

Diagrama correspondente: [diagramas/classes.puml](diagramas/classes.puml).

## Conceitos do domínio

| Conceito | Dono | Descrição |
|---|---|---|
| Usuário | `users` | Pessoa com conta no SIGA, identificada pelo nome (chave primária). Não guarda senha. |
| Credencial | `auth` | Par nome de usuário e hash SHA-512 da senha. |
| Sessão | `auth` | Token UUID gerado no login e apagado no logout. |
| Evento | `event_registration` | Atividade acadêmica com identificador e nome. |
| Inscrição | pendente | Vínculo entre usuário e evento, com situação (confirmada, em espera, cancelada). |
| Presença | pendente | Registro de que um inscrito compareceu ao evento. |

Os serviços não compartilham objetos. O único dado que cruza fronteiras é o
**nome do usuário** (entre `users` e `auth`) e o **token** (entre o cliente,
`event_registration` e `auth`). Inscrição e presença vão se referir a usuário e
evento apenas por identificador.

## Responsabilidades por módulo

### `auth` (Go)

| Elemento | Responsabilidade |
|---|---|
| `router` | Liga cada rota HTTP ao seu *handler*. |
| `login`, `logout`, `credentials`, `authenticated` | *Handlers*: leem a requisição, chamam o repositório e escolhem o status HTTP. |
| `repository` | Única parte que conhece o SQLite. Grava e consulta credenciais e sessões. |
| `Credential` | Estrutura de dados da credencial. |

### `users` (Elixir/Phoenix)

| Elemento | Responsabilidade |
|---|---|
| `UserController`, `SessionController` | Recebem as requisições HTTP e delegam ao contexto `Accounts`. |
| `FallbackController` | Converte erros (`{:error, ...}`) em status HTTP e corpo JSON, num só lugar. |
| `UserJSON`, `ChangesetJSON`, `ErrorJSON` | Visões: formatam as respostas JSON. |
| `Accounts` | Contexto (serviço de aplicação): caso de uso "criar conta", com a transação que mantém `users` e `auth` consistentes. |
| `Accounts.User` | Esquema e validação do usuário (nome obrigatório, até 64 caracteres, único). A senha é campo virtual, nunca persistido. |
| `Auth` | *Gateway* HTTP para o serviço `auth`. Traduz respostas e falhas de rede em `:ok` e `{:error, motivo}`. |
| `Repo` | Acesso ao SQLite via Ecto. |

### `event_registration` (Zig)

| Elemento | Responsabilidade |
|---|---|
| `main` | Lê as opções de linha de comando e a variável `SIGA_AUTH_URL` e inicia o servidor. |
| `options` | Interpreta `-address` e `-port`. |
| `server` | Rotas e *handlers* HTTP. `requireAuth` exige token válido antes de qualquer operação. |
| `auth` | Cliente do serviço `auth`. Extrai o token do cabeçalho `Authorization: Bearer` e devolve um `Result` (`authenticated`, `missing_token`, `invalid_token`, `unavailable`). |
| `repository` | Única parte que conhece o SQLite. Insere e consulta eventos. |
| `Event`, `EventEntry` | Estruturas de dados do evento. |

## GRASP

- **Controller**: `UserController`, `SessionController` e os *handlers* de
  `server.zig` e do `auth` recebem os eventos de sistema (requisições) e
  delegam o trabalho. Não contêm regra de persistência.
- **Information Expert**: `Accounts.User` valida o usuário porque conhece seus
  campos e restrições. `repository` responde se uma sessão existe porque é quem
  tem acesso à tabela de sessões.
- **Pure Fabrication**: `repository` (nos três serviços), `Users.Auth` e
  `auth.zig` não são conceitos do domínio. Existem para tirar dos objetos de
  domínio e dos controladores o acesso a banco e a rede.
- **Indirection** e **Protected Variations**: os outros serviços nunca falam
  com o `auth` diretamente, e sim pelos adaptadores `Users.Auth` e `auth.zig`.
  O que pode variar (URL, formato da resposta, o próprio provedor de
  autenticação) fica escondido atrás de uma interface pequena: `create_credentials/2`
  e `login/2` em Elixir, `authenticate()` devolvendo `Result` em Zig. É isso
  que permite trocar o provedor (ASR-2).
- **Low Coupling**: os serviços dependem só do contrato HTTP uns dos outros,
  nunca do banco ou do código alheio.

## Coesão e acoplamento

**Coesão alta**: cada serviço cuida de um único assunto (identidade, contas,
eventos). Dentro de cada um, há separação entre entrada HTTP, regra e
persistência.

**Acoplamento entre serviços**: baixo e explícito. É só HTTP/JSON síncrono,
listado na [documentação de API](arquitetura.md#documentação-de-api). Pontos que
ainda acoplam mais do que deveriam:

- `SessionController` repassa a resposta do `auth` **sem alterações**. O cliente
  fica preso ao formato do `auth` (por exemplo, o campo `Token` com inicial
  maiúscula, padrão do Go). Trocar o `auth` mudaria a resposta do `users`.
- Toda requisição de eventos chama o `auth` (acoplamento temporal): se o `auth`
  cair, eventos para de responder com sucesso. Esse custo foi aceito em troca da
  revogação imediata de sessões ([ADR-003](adr/ADR-003.md)).

**Acoplamento dentro dos serviços**:

- `server.zig` e o repositório do `auth` em Go guardam a conexão com o banco
  em variável global. No `auth`, o banco é aberto explicitamente por
  `repository.Open(caminho)`, chamado pelo `main` (opção `-db`), o que permite
  aos testes usar um banco temporário. Ainda assim não dá para trocar o
  repositório por um falso. Passar essas dependências por parâmetro, atrás de
  uma interface, seria o próximo passo.
- Em `users`, o adaptador `Users.Auth` lê opções extras do ambiente
  (`:auth_req_options`). Nos testes isso injeta um *stub* (`Req.Test`) no lugar
  do `auth` real, sem mudar o código de produção.

## SOLID

- **SRP**: em `users`, validação (`User`), caso de uso (`Accounts`), integração
  (`Auth`), formatação (`*JSON`) e mapeamento de erros (`FallbackController`)
  estão em módulos separados. Cada um muda por um motivo diferente.
- **OCP**: um novo erro de domínio em `users` é tratado acrescentando uma
  cláusula ao `FallbackController`, sem alterar os controladores.
- **DIP**: os casos de uso dependem de uma abstração da autenticação
  (`Users.Auth`, `auth.Result`), não do protocolo HTTP do `auth`. A inversão
  ainda é parcial: em Elixir a troca de implementação é feita por configuração
  e não por um `@behaviour` explícito, e em Zig o cliente é uma estrutura
  concreta. Definir um `behaviour` `Users.AuthProvider`, com implementações
  HTTP e falsa, completaria o princípio.
- **ISP**: cada adaptador expõe só o que seu serviço usa. `users` não sabe
  validar tokens e `event_registration` não sabe criar credenciais.
