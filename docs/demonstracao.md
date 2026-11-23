# Roteiro de demonstração

Uma sequência de chamadas com `curl` que passa por todos os serviços, pelos
fluxos principais e pelos erros mais interessantes. Os comandos usam `jq` para
guardar tokens e ids em variáveis. Cada bloco depende das variáveis dos blocos
anteriores, então rode tudo no mesmo terminal.

As respostas mostradas nos comentários foram obtidas rodando o roteiro. Os ids
podem mudar: o serviço de eventos cria um evento de exemplo ("Main event") ao
subir, e o banco guarda o que já foi feito antes.

```sh
SIGA=http://siga.gboncoffee.dev.br
JSON='content-type: application/json'
alias curl='curl -w "\n"'
```

O `alias` só serve para o terminal ficar legível: as respostas de `users` e de
eventos não terminam com quebra de linha, e sem ele o prompt aparece colado na
resposta.

Para rodar sem o nginx, na própria máquina, cada serviço tem sua porta (ver o
[README](../README.md)). Troque `$SIGA` por `localhost:4000` nas chamadas de
contas, `localhost:16000` nas de eventos e `localhost:8081` nas de inscrições.

## 1. Contas (`users`)

Criar duas contas. O `users` grava o nome e pede ao `auth` para guardar a
credencial.

```sh
curl -si -X POST $SIGA/users -H "$JSON" -d '{"name": "ana", "password": "segredo"}'
# 201 {"name":"ana"}

curl -si -X POST $SIGA/users -H "$JSON" -d '{"name": "bob", "password": "outrosegredo"}'
# 201 {"name":"bob"}
```

Nome repetido e senha faltando:

```sh
curl -si -X POST $SIGA/users -H "$JSON" -d '{"name": "ana", "password": "qualquer"}'
# 409 {"errors":{"name":["has already been taken"]}}

curl -si -X POST $SIGA/users -H "$JSON" -d '{"name": "carla"}'
# 422 {"errors":{"password":["can't be blank"]}}
```

Se for repetir a demonstração no mesmo servidor, `ana` e `bob` já vão existir e
as duas primeiras chamadas dão 409. O resto do roteiro funciona igual.

## 2. Login

O `users` repassa o login ao `auth`, que devolve um token de sessão.

```sh
curl -si -X POST $SIGA/login -H "$JSON" -d '{"name": "ana", "password": "segredo"}'
# 200 {"Token":"e2e99a2c-f198-4324-bce9-287d695092d8"}

curl -si -X POST $SIGA/login -H "$JSON" -d '{"name": "ana", "password": "errada"}'
# 401 invalid username or password
```

Guardar um token para cada usuário:

```sh
ANA=$(curl -s -X POST $SIGA/login -H "$JSON" -d '{"name": "ana", "password": "segredo"}' | jq -r .Token)
BOB=$(curl -s -X POST $SIGA/login -H "$JSON" -d '{"name": "bob", "password": "outrosegredo"}' | jq -r .Token)
echo "ana: $ANA"; echo "bob: $BOB"
```

## 3. Eventos (`event_registration`)

Sem token, ou com um token que não é de nenhuma sessão, a resposta é 401. O
serviço de eventos pergunta ao `auth` em toda requisição.

```sh
curl -si $SIGA/event
# 401 {"error":"missing or malformed token"}   (com WWW-Authenticate: Bearer)

curl -si $SIGA/event -H "Authorization: Bearer 00000000-0000-0000-0000-000000000000"
# 401 {"error":"invalid token"}
```

Cadastrar eventos. A resposta traz o cabeçalho `Location`:

```sh
curl -si -X POST $SIGA/event -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d '{"name": "Semana Acadêmica de Computação"}'
# 201 Location: /event/58
#     {"id":58,"name":"Semana Acadêmica de Computação"}

EVENTO=$(curl -s -X POST $SIGA/event -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d '{"name": "Minicurso de Zig"}' | jq .id)
echo "evento: $EVENTO"
```

Listar e consultar, agora como `bob`:

```sh
curl -si $SIGA/event -H "Authorization: Bearer $BOB"
# 200 [{"id":57,"name":"Main event"},{"id":58,"name":"Semana Acadêmica de Computação"},{"id":59,"name":"Minicurso de Zig"}]

curl -si $SIGA/event/$EVENTO -H "Authorization: Bearer $BOB"
# 200 {"id":59,"name":"Minicurso de Zig"}

curl -si $SIGA/event/9999 -H "Authorization: Bearer $BOB"
# 404 {"error":"not found"}

curl -si -X POST $SIGA/event -H "Authorization: Bearer $ANA" -H "$JSON" -d '{"name": ""}'
# 400 {"error":"name is empty"}
```

## 4. Inscrições (`signups`)

A inscrição é sempre de quem é dono do token. Basta mandar o evento. O
`signups` pergunta ao `auth` de quem é o token e ao `event_registration` se o
evento existe.

```sh
curl -si -X POST $SIGA/signup -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d "{\"event_id\": $EVENTO}"
# 201 {"id":1,"username":"ana","event_id":59,"presence_confirmed":0}
```

Inscrição repetida e evento inexistente:

```sh
curl -si -X POST $SIGA/signup -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d "{\"event_id\": $EVENTO}"
# 409 already signed up for this event

curl -si -X POST $SIGA/signup -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d '{"event_id": 9999}'
# 404 event service: 404
```

`bob` tenta inscrever a `ana`, e depois se inscreve:

```sh
curl -si -X POST $SIGA/signup -H "Authorization: Bearer $BOB" -H "$JSON" \
  -d "{\"username\": \"ana\", \"event_id\": $EVENTO}"
# 403 cannot act on behalf of another user

curl -si -X POST $SIGA/signup -H "Authorization: Bearer $BOB" -H "$JSON" \
  -d "{\"event_id\": $EVENTO}"
# 201 {"id":2,"username":"bob","event_id":59,"presence_confirmed":0}
```

## 5. Presença

`bob` não consegue marcar a presença da `ana`. A própria `ana` consegue:

```sh
curl -si -X PUT $SIGA/presence -H "Authorization: Bearer $BOB" -H "$JSON" \
  -d "{\"username\": \"ana\", \"event_id\": $EVENTO, \"presence_confirmed\": 1}"
# 403 cannot act on behalf of another user

curl -si -X PUT $SIGA/presence -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d "{\"event_id\": $EVENTO, \"presence_confirmed\": 1}"
# 200
```

Consultar a inscrição. O id vem da resposta do `POST /signup`:

```sh
curl -si $SIGA/signup/1 -H "Authorization: Bearer $ANA"
# 200 {"id":1,"username":"ana","event_id":59,"presence_confirmed":1}
```

## 6. `auth` fora do ar (ASR-3)

Esta parte mostra o requisito de que a queda do `auth` não derruba os outros
serviços. Na máquina do servidor, pare o processo do `auth` e rode:

```sh
curl -si $SIGA/event -H "Authorization: Bearer $ANA"
# 503 {"error":"auth service unavailable"}

curl -si -X POST $SIGA/signup -H "Authorization: Bearer $ANA" -H "$JSON" \
  -d "{\"event_id\": $EVENTO}"
# 503 auth service unavailable

curl -si -X POST $SIGA/login -H "$JSON" -d '{"name": "ana", "password": "segredo"}'
# 503 {"errors":{"detail":"auth service unavailable"}}

curl -si -X POST $SIGA/users -H "$JSON" -d '{"name": "carla", "password": "x"}'
# 503 {"errors":{"detail":"auth service unavailable"}}
```

As respostas são imediatas, e nenhum serviço cai. Suba o `auth` de novo. As
sessões ficam no banco do `auth`, então os tokens continuam valendo:

```sh
curl -si $SIGA/event/$EVENTO -H "Authorization: Bearer $ANA"
# 200 {"id":59,"name":"Minicurso de Zig"}
```

E a conta `carla` não ficou criada pela metade. O `users` desfez a gravação
quando o `auth` falhou, então dá para criá-la agora:

```sh
curl -si -X POST $SIGA/users -H "$JSON" -d '{"name": "carla", "password": "x"}'
# 201 {"name":"carla"}
```

## O que não dá para mostrar pela API

- O `auth` não é acessível de fora ([ADR-005](adr/ADR-005.md)). Por isso o
  logout (`POST /logout/{uuid}`) ainda não está disponível para o cliente.
- Vagas, lista de espera e cancelamento de inscrição ainda não existem (ver
  [requisitos](requisitos.md)).
