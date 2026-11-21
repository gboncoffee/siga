# Arquitetura

Diagrama correspondente: [diagramas/componentes.puml](diagramas/componentes.puml).

## Organização

```
Cliente-servidor (cliente HTTP -> serviços)
        +
Microsserviços por assunto (auth, users, event_registration, inscrições*)
        +
Um banco por serviço (SQLite em arquivo)
        +
Comunicação síncrona HTTP/JSON
        +
Camadas dentro de cada serviço (entrada HTTP -> regra -> persistência / gateway)
```

\* serviço de inscrições ainda em desenvolvimento.

Como cada estilo aparece no código:

- **Cliente-servidor**: o cliente (hoje `curl` ou os testes) fala só HTTP com
  `users` e `event_registration`. Nenhum cliente acessa o `auth`, que escuta
  apenas em `localhost` ([ADR-005](adr/ADR-005.md)).
- **Microsserviços**: três processos independentes, cada um com seu
  diretório no repositório, sua linguagem, sua forma de compilar e seus testes
  ([ADR-001](adr/ADR-001.md)).
- **Banco por serviço**: `auth/db.db`, `event_registration/events.db` e o banco
  do `users` (`DATABASE_PATH`). Nenhum serviço abre o banco de outro
  ([ADR-002](adr/ADR-002.md)).
- **Camadas**: em todos os serviços o *handler* ou controlador HTTP não executa
  SQL. Ele chama um repositório (`repository` em Go e Zig, `Repo` com Ecto em
  Elixir). Em `users` há ainda uma camada de aplicação (`Accounts`) entre o
  controlador e o repositório, e as visões JSON fazem o papel do V do MVC.

## Componentes

| Componente | Linguagem | Porta padrão | Responsabilidade | Persistência | Depende de |
|---|---|---|---|---|---|
| `auth` | Go (`net/http`) | 8080, só `localhost` | Credenciais (hash da senha) e sessões (tokens UUID). Responde se um token é válido. | SQLite `db.db` (opção `-db`): tabelas `credentials` e `sessions` | — |
| `users` | Elixir/Phoenix | 4000 | Cadastro de contas (nomes) e porta de entrada do login. | SQLite via Ecto: tabela `users` | `auth` |
| `event_registration` | Zig (`httpz`) | 16000 | Cadastro e consulta de eventos, exigindo sessão válida. | SQLite `events.db`: tabela `events` | `auth` |
| inscrições | — | — | Inscrições, vagas, lista de espera e presença (RF06 a RF09). | Banco próprio | `auth`, `event_registration` |

## Comunicação

Todas as chamadas são HTTP/1.1 síncronas com corpo JSON ([ADR-004](adr/ADR-004.md)).

| Origem | Destino | Chamada | Quando |
|---|---|---|---|
| `users` | `auth` | `POST /credentials` | Criação de conta, dentro da transação do `users` |
| `users` | `auth` | `POST /login` | Login. A resposta é repassada ao cliente. |
| `event_registration` | `auth` | `GET /{token}` | Em **toda** requisição de eventos, antes de qualquer operação |

O token vai do cliente para os serviços no cabeçalho
`Authorization: Bearer <uuid>`. O `event_registration` confere se ele é um UUID
bem formado antes de colocá-lo na URL do `auth`.

**Tratamento de falha** (ASR-3):

- `users` usa tempo limite de 5 s e nenhuma nova tentativa (`retry: false`).
  Com o `auth` inacessível, responde 503. Se o `auth` recusar a credencial,
  responde 502. Nos dois casos a transação é desfeita e o nome não fica gravado.
- `event_registration` responde 503 (`auth service unavailable`) quando não
  consegue falar com o `auth` ou recebe um status inesperado. **Pendência**: o
  cliente HTTP do Zig ainda não define tempo limite, então um `auth` travado
  (que aceita a conexão mas não responde) seguraria a requisição.

## Interfaces relevantes

| Interface | Onde | Para que serve |
|---|---|---|
| Contrato HTTP do `auth` | `auth/router.go` | Única forma de os outros serviços usarem autenticação. |
| `Users.Auth.create_credentials/2`, `login/2` | `users/lib/users/auth.ex` | Gateway que esconde o HTTP do `auth` do resto do `users`. Nos testes é substituído por um *stub* `Req.Test`. |
| `Auth.authenticate(header) -> Result` | `event_registration/src/auth/auth.zig` | Gateway que transforma a resposta do `auth` em quatro resultados de domínio. |
| `repository` | os três serviços | Separa SQL do restante do código. |

## Integrações externas

A dependência substituível do projeto é o **serviço de autenticação** (seção 8
do enunciado, exemplo "ServicoAutenticacao"). Ele é um processo separado e só é
acessado pelos gateways acima. Os testes do `users` rodam sem o `auth` real,
usando o *stub* configurado em `config/test.exs`
(`config :users, :auth_req_options, plug: {Req.Test, Users.Auth}`).

Hoje não há integração com sistemas fora do SIGA. Candidatos naturais são o
login institucional da universidade (ver [evolução](tradeoffs.md#análise-de-evolução))
e o envio de e-mail de confirmação de inscrição.

## Segurança (limitações aceitas no protótipo)

- As senhas são guardadas como SHA-512 **sem sal**. Num sistema real seria
  preciso um algoritmo próprio para senhas (Argon2 ou bcrypt). A troca fica
  contida no `auth`.
- Sessões não expiram. Só o logout as remove.
- Não há autenticação entre serviços: a proteção do `POST /credentials` é o
  `auth` só aceitar conexões de `localhost` ([ADR-005](adr/ADR-005.md)).
- Não há papéis: qualquer usuário autenticado pode cadastrar eventos. O ator
  Organizador ainda não é diferenciado.

## Documentação de API

Respostas de erro de `event_registration` têm a forma `{"error": "..."}`. As de
`users` têm a forma `{"errors": {...}}`.

### `auth` (interno, só `localhost:8080`)

| Rota | Corpo | Respostas |
|---|---|---|
| `POST /credentials` | `{"Username": "...", "Password": "..."}` | 200; 400 JSON inválido; 500 erro ao gravar (inclui nome repetido) |
| `POST /login` | `{"Username": "...", "Password": "..."}` | 200 `{"Token": "<uuid>"}`; 400 JSON inválido; 401 nome ou senha inválidos |
| `POST /logout/{uuid}` | — | 200; 400 token malformado |
| `GET /{uuid}` | — | 200 sessão existe; 400 token malformado; 401 sessão não existe |

### `users` (`:4000`)

| Rota | Corpo | Respostas |
|---|---|---|
| `POST /users` | `{"name": "...", "password": "..."}` | 201 `{"name": "..."}`; 409 nome em uso; 422 campos inválidos; 502 `auth` recusou; 503 `auth` fora do ar |
| `POST /login` | `{"name": "...", "password": "..."}` | resposta do `auth` sem alterações; 400 sem nome ou senha; 503 `auth` fora do ar |

### `event_registration` (`:16000`)

Todas as rotas exigem `Authorization: Bearer <uuid>`. Sem token, ou com token
inválido, a resposta é 401 com `WWW-Authenticate: Bearer`. Com o `auth` fora do
ar, a resposta é 503.

| Rota | Corpo | Respostas |
|---|---|---|
| `GET /event` | — | 200 `[{"id": 1, "name": "..."}]` |
| `GET /event/{id}` | — | 200 `{"id": 1, "name": "..."}`; 400 id inválido; 404 não existe |
| `POST /event` | `{"name": "..."}` | 201 `{"id": 2, "name": "..."}` com cabeçalho `Location: /event/2`; 400 corpo inválido, nome vazio ou com mais de 128 bytes |

## Testes

| Serviço | Comando | Cobertura atual |
|---|---|---|
| `users` | `mix test` | Controladores e o contexto `Accounts`, incluindo rollback quando o `auth` recusa ou está fora, com o `auth` substituído por *stub* |
| `event_registration` | `zig build test` | Testes de unidade de `options` e de `auth` (leitura do cabeçalho e validação de UUID) |
| `auth` | `go test ./...` | Repositório (credenciais, nome repetido, ciclo de vida da sessão) e as rotas HTTP reais via `httptest`: login, logout, senha errada, usuário desconhecido, token malformado, JSON inválido e método não permitido. Cada execução usa um banco temporário. |
