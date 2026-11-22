# signups

Serviço de inscrições do SIGA, em Go.

Guarda a associação entre nome de usuário, id do evento e presença.

## Rotas

Todas as rotas exigem `Authorization: Bearer <token>`, com um token obtido no
login (`POST /login` do `users`). Sem token, ou com token inválido, a resposta
é 401. Com o `auth` fora do ar, 503. Os erros vêm em texto puro.

O usuário é sempre o dono do token, informado pelo `auth`. Ninguém inscreve
outra pessoa nem mexe na presença de outra pessoa. O campo `username` no corpo
é opcional. Se vier com outro nome, a resposta é 403.

| Rota | Corpo | Resposta |
|---|---|---|
| `POST /signup` | `{"event_id": 1}` | 201 `{"id": 1, "username": "ana", "event_id": 1, "presence_confirmed": 0}`; 400 JSON inválido; 403 `username` de outro usuário; 404 evento não existe; 409 inscrição já existe (mesmo usuário e evento); 503 serviço de eventos fora do ar |
| `PUT /presence` | `{"event_id": 1, "presence_confirmed": 1}` | 200 e grava `presence_confirmed` (1 confirma, 0 desfaz) na inscrição do usuário; 400 JSON inválido ou `presence_confirmed` diferente de 0 e 1; 403 `username` de outro usuário; 404 o usuário não está inscrito no evento |
| `GET /signup/{id}` | | 200 `{"id": 1, "username": "ana", "event_id": 1, "presence_confirmed": 0}`; 400 id inválido; 404 inscrição não encontrada |

Na inscrição, o serviço consulta `GET /event/{id}` no `event_registration`,
repassando o token do cliente, para confirmar que o evento existe.

## Rodando

```sh
go run . -port 8081 -address localhost \
  -auth-url http://localhost:8080 -event-url http://localhost:16000
```

Os valores acima são os padrões. O banco SQLite fica em `db.db` (opção `-db`).

## Testes

```sh
go test ./...
```

Os testes sobem o serviço com `httptest`, com `auth` e serviço de eventos
falsos e um banco temporário.

## Limitações

- Sem papel de organizador, cada participante confirma a própria presença.
- `GET /signup/{id}` mostra a inscrição de qualquer usuário a qualquer usuário
  autenticado.
- Ainda não há vagas, lista de espera nem cancelamento.
