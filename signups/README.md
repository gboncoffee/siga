# signup
Serviço de inscrição (signup) do SIGA, em GO.

Armazena associação Nome Usuario, ID evento, presença.

## Rotas

| Rota | Corpo | Resposta |
|---|---|---|
| `POST /signup` | `{"username": "...", "event_id": "..."}`  | 201 `{"id": "...", "username": "...", "event_id": "...", "presence_confirmed": "0"}`; 400 em erro de json ou seu conteudo campos; 409 se inscrição já existir (combinação usuario, evento_id) |
| `PUT /presence` | `{"username": "...", "event_id": "..."}, "presence_confirmed": "0/1"` | 200 e atualiza valor de presence_confirmed com valor enviado; 400 se presence confirmed != 0/1 ou JSON invalido ;404 se inscrição não encontrada |
| `GET /signup/{id}` | | 200 `{"id": "...", "username": "...", "event_id": "...", "presence_confirmed": "0/1"}`; 400 em ID invalido; 404 em signup não encontrado |


### Rodando
```sh
./signups -port <portAddr> # default 8081   
          -address <addrListenTo> # default localhost
          -auth-url <url> # default http://localhost:8080
          -event-url <url>  # default http://localhost:16000
```

#### Comentarios Gerais / Detalhes Funcionamento
Na implementação atual, todas requisições validam um token providenciado pelo serviço de autenticação. O token deve estar no header
(Exemplo curl -s localhost:8081/signup/1 -H "$AUTH", onde AUTH contém o token gerado no login). 
Caso o usuário esteja logado/com token valido pode realizar requisições do serviço de signup.
O serviço NÃO CHECA se o usuário está fazendo uma requisição/registro em seu nome ou em nome de outro. Nomes de usuários também podem
ser de usuários não registrados no serviço de usuário/autenticação. Qualquer usuário autenticado também pode alterar presença de qualquer
inscrição se souber (username, evento_id).

REPITO: REQUISIÇÕES ESPERAM TOKEN VALIDO DO SERVIÇO AUTH NO HEADER.

#####
SGBD usado: SQLITE
Linguagem: GO