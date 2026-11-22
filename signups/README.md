# signups

Serviço de inscrições do SIGA, em Go.

Guarda a associação entre nome de usuário, id do evento e presença.

## Rotas

Todas as rotas exigem `Authorization: Bearer <token>`, com um token obtido no
login (`POST /login` do `users`). Sem token, ou com token inválido, a resposta
é 401. Com o `auth` fora do ar, 503. Os erros vêm em texto puro.

| Rota | Corpo | Resposta |
|---|---|---|
| `POST /signup` | `{"username": "ana", "event_id": 1}` | 201 `{"id": 1, "username": "ana", "event_id": 1, "presence_confirmed": 0}`; 400 JSON inválido ou `username` vazio; 404 evento não existe; 409 inscrição já existe (mesmo usuário e evento); 503 serviço de eventos fora do ar |
| `PUT /presence` | `{"username": "ana", "event_id": 1, "presence_confirmed": 1}` | 200 e grava `presence_confirmed` (1 confirma, 0 desfaz); 400 JSON inválido ou `presence_confirmed` diferente de 0 e 1; 404 inscrição não encontrada |
| `GET /signup/{id}` | | 200 `{"id": 1, "username": "ana", "event_id": 1, "presence_confirmed": 0}`; 400 id inválido; 404 inscrição não encontrada |

Na inscrição, o serviço consulta `GET /event/{id}` no `event_registration`,
repassando o token do cliente, para confirmar que o evento existe.

## Rodando

```sh
go run . -port 8081 -address localhost \
  -auth-url http://localhost:8080 -event-url http://localhost:16000
```

Os valores acima são os padrões. O banco SQLite fica em `db.db`, no diretório
onde o serviço foi iniciado.

## Limitações

- O serviço só verifica se o token é válido, não *de quem* ele é. Um usuário
  autenticado pode inscrever outro nome, ou marcar presença em qualquer
  inscrição, se souber o nome e o id do evento.
- O nome do usuário não é conferido no `users`: pode ser de alguém sem conta.
- Ainda não há vagas, lista de espera nem cancelamento.
