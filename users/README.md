# users

Serviço de usuários do SIGA, em Elixir com Phoenix (só API JSON).

Guarda apenas a lista de nomes. As senhas ficam no serviço `auth`, que é
chamado na criação e no login.

## Rotas

| Rota | Corpo | Resposta |
|---|---|---|
| `POST /users` | `{"name": "...", "password": "..."}` | 201 `{"name": "..."}`; 409 nome em uso; 422 campos inválidos; 502/503 erro no auth |
| `POST /login` | `{"name": "...", "password": "..."}` | a resposta do `POST /login` do auth, sem alterações; 400 sem nome ou senha; 503 auth fora do ar |

Na criação, o nome é gravado numa transação que é desfeita se o auth não
aceitar as credenciais.

## Rodando

```sh
mix setup                                  # dependências e banco
SIGA_AUTH_URL=http://localhost:8080 PORT=4000 mix phx.server
mix test
```

| Variável | Padrão |
|---|---|
| `PORT` | `4000` |
| `SIGA_AUTH_URL` | `http://localhost:8080` |
| `DATABASE_PATH` | obrigatória em produção |

## Estrutura (MVC)

- Model: `lib/users/accounts/user.ex` (schema e validações) e o contexto
  `lib/users/accounts.ex`.
- Cliente do auth: `lib/users/auth.ex`.
- Controllers: `lib/users_web/controllers/{user,session,fallback}_controller.ex`.
- Views: `lib/users_web/controllers/{user,changeset,error}_json.ex`.
