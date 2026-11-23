# SIGA - Sistema Interativo de Gestão de Atividades

Sistema implementado para a disciplina de Design de Software. Tema: eventos
acadêmicos e inscrições.

## Documentação

- [Requisitos e ASRs](docs/requisitos.md)
- [Modelo de domínio e responsabilidades](docs/dominio.md)
- [Arquitetura e documentação de API](docs/arquitetura.md)
- [Alternativas, trade-offs e análise de evolução](docs/tradeoffs.md)
- [Roteiro de demonstração com `curl`](docs/demonstracao.md)
- Decisões arquiteturais:
  - [ADR-001: Microsserviços por assunto](docs/adr/ADR-001.md)
  - [ADR-002: Um banco SQLite por serviço](docs/adr/ADR-002.md)
  - [ADR-003: Token opaco validado a cada requisição](docs/adr/ADR-003.md)
  - [ADR-004: Comunicação síncrona HTTP/JSON](docs/adr/ADR-004.md)
  - [ADR-005: `auth` acessível só pela máquina local](docs/adr/ADR-005.md)
- Diagramas (fonte PlantUML `.puml` e imagem `.png` em
  [docs/diagramas](docs/diagramas)):
  - [Classes](docs/diagramas/classes.png)
  - [Sequência: cadastrar evento](docs/diagramas/sequencia.png)
  - [Sequência: criar conta](docs/diagramas/sequencia-cadastro.png)
  - [Sequência: inscrever em evento](docs/diagramas/sequencia-inscricao.png)
  - [Comunicação: login](docs/diagramas/comunicacao.png)
  - [Componentes](docs/diagramas/componentes.png)

  Para gerar as imagens de novo: `cd docs/diagramas && plantuml -tpng *.puml`.

### Site da documentação

`docs/site/build.sh` converte os `.md` de `docs/` em um site estático (HTML,
CSS e diagramas em SVG) no diretório `site/`. Precisa de `pandoc` e
`plantuml`. O diretório gerado pode ser copiado para qualquer servidor web.

```sh
docs/site/build.sh              # gera em site/
docs/site/build.sh /outro/dir   # gera em outro diretório
```

## Serviços

| Diretório | Linguagem | Porta padrão | Função |
|---|---|---|---|
| [auth](auth) | Go | `localhost:8080` | Credenciais e sessões |
| [users](users) | Elixir/Phoenix | 4000 | Contas e login |
| [event_registration](event_registration) | Zig | 16000 | Eventos |
| [signups](signups) | Go | 8081 | Inscrições e presença |

## Rodando

Cada serviço roda num terminal separado. O `auth` precisa subir primeiro.

```sh
cd auth && go run . -port 8080
```

```sh
cd users && mix setup && SIGA_AUTH_URL=http://localhost:8080 mix phx.server
```

```sh
cd event_registration && SIGA_AUTH_URL=http://localhost:8080 zig build run -- -port 16000
```

```sh
cd signups && go run . -port 8081 -auth-url http://localhost:8080 -event-url http://localhost:16000
```

Exemplo de uso (um roteiro completo está em
[docs/demonstracao.md](docs/demonstracao.md)):

```sh
curl -X POST localhost:4000/users -H 'content-type: application/json' \
  -d '{"name": "ana", "password": "segredo"}'
TOKEN=$(curl -s -X POST localhost:4000/login -H 'content-type: application/json' \
  -d '{"name": "ana", "password": "segredo"}' | jq -r .Token)
curl -X POST localhost:16000/event -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"name": "Semana Acadêmica"}'
curl localhost:16000/event -H "Authorization: Bearer $TOKEN"
curl -X POST localhost:8081/signup -H "Authorization: Bearer $TOKEN" \
  -d '{"event_id": 1}'
curl -X PUT localhost:8081/presence -H "Authorization: Bearer $TOKEN" \
  -d '{"event_id": 1, "presence_confirmed": 1}'
curl localhost:8081/signup/1 -H "Authorization: Bearer $TOKEN"
```

## Testes

```sh
cd auth && go test ./...
```

```sh
cd users && mix test
```

```sh
cd event_registration && zig build test
```

```sh
cd signups && go test ./...
```
