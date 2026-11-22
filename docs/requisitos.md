# Requisitos

## Contexto

O SIGA (Sistema Interativo de Gestão de Atividades) organiza os eventos
acadêmicos de uma universidade: semanas acadêmicas, palestras, minicursos e
oficinas. Organizadores cadastram eventos e vagas, e a comunidade acadêmica se
inscreve, cancela inscrições e tem a presença registrada. Esse é o tema 8 do
trabalho, "Eventos acadêmicos e inscrições".

Hoje esses eventos costumam ser organizados com formulários e planilhas
avulsas, sem controle de vagas, sem lista de espera e sem registro confiável de
presença para emitir certificados.

## Atores

| Ator | Descrição |
|---|---|
| Participante | Estudante, servidor ou visitante com conta no SIGA. Consulta eventos, se inscreve e cancela inscrições. |
| Organizador | Responsável por um evento. Cadastra eventos e atividades, define vagas e registra presença. |
| Serviço de autenticação | Ator de sistema. Guarda credenciais e sessões e responde se um token é válido. É a dependência substituível do projeto (seção 8 do enunciado). |

## Requisitos funcionais

A coluna "Situação" diz o que o protótipo já implementa.

| Id | Requisito | Situação |
|---|---|---|
| RF01 | O sistema deve permitir criar uma conta com nome e senha. O nome é único. | Implementado (`users`, `POST /users`) |
| RF02 | O usuário deve poder entrar com nome e senha e receber um token de sessão. | Implementado (`users`, `POST /login`, repassado ao `auth`) |
| RF03 | O usuário deve poder encerrar a sessão, invalidando o token. | Parcial: existe no `auth` (`POST /logout/{uuid}`), mas ainda não está exposto ao cliente |
| RF04 | O organizador deve poder cadastrar um evento. | Implementado (`event_registration`, `POST /event`) |
| RF05 | Usuários autenticados devem poder listar os eventos e consultar um evento pelo identificador. | Implementado (`GET /event`, `GET /event/{id}`) |
| RF06 | O participante deve poder se inscrever em um evento enquanto houver vagas. | Parcial: a inscrição existe (`signups`, `POST /signup`), confere se o evento existe e impede inscrição repetida, mas eventos ainda não têm vagas |
| RF07 | Com o evento lotado, a inscrição deve entrar numa lista de espera, por ordem de chegada. | Pendente |
| RF08 | O participante deve poder cancelar a inscrição. A vaga liberada vai para o primeiro da lista de espera. | Pendente |
| RF09 | O organizador deve poder registrar a presença dos inscritos. | Parcial: `PUT /presence` e `GET /signup/{id}` existem, mas qualquer usuário autenticado pode registrar presença, pois ainda não há papel de organizador |

## Restrições

- **Prazo e equipe**: trabalho de disciplina, feito por uma equipe pequena em um
  semestre. Cada integrante desenvolve uma parte de forma independente.
- **Funcionalidades bem distintas**: identidade, contas, eventos e inscrições
  têm regras, dados e ritmos de mudança próprios e quase não compartilham
  lógica. Novas funcionalidades (certificados, notificações) tendem a ser
  igualmente independentes.
- **Linguagens diferentes**: os serviços são escritos em Go (`auth` e
  `signups`), Zig (`event_registration`) e Elixir/Phoenix (`users`). Não há biblioteca
  compartilhada entre eles, então o contrato entre as partes tem de ser
  independente de linguagem.
- **Uma única máquina**: o protótipo roda todo em uma máquina, sem
  orquestrador nem nuvem. O `auth` escuta só em `localhost` (ver
  [ADR-005](adr/ADR-005.md)).
- **Persistência simples**: cada serviço usa SQLite em arquivo local, sem
  servidor de banco para instalar.
- **Sem interface gráfica**: o protótipo expõe apenas APIs HTTP/JSON. A
  interface é exercitada com `curl` ou com os testes.

## Requisitos arquiteturalmente significativos (ASRs)

### ASR-1: evolução e implantação independentes das partes

**Cenário**: um integrante altera o serviço de eventos (por exemplo, para
acrescentar vagas ao evento). A mudança deve ser compilada, testada e posta no
ar **sem recompilar, reiniciar ou alterar o código de `auth` ou `users`**,
desde que o contrato HTTP publicado continue o mesmo.

O mesmo vale para acrescentar uma funcionalidade nova (por exemplo, emissão de
certificados a partir das presenças): ela deve poder entrar como uma parte
nova, consumindo as APIs existentes, sem alterar o código das partes atuais.

**Por que influencia a arquitetura**: com três linguagens e desenvolvimento em
paralelo, não existe um processo único onde todos os módulos possam morar. E
como as funcionalidades são bem distintas entre si, uma fronteira forte entre
elas custa pouco (há pouca chamada cruzada) e mantém cada uma coesa. Isso
leva à divisão em serviços separados com contrato HTTP/JSON
([ADR-001](adr/ADR-001.md), [ADR-004](adr/ADR-004.md)) e a um banco por serviço,
para que a mudança de esquema de um não quebre os outros
([ADR-002](adr/ADR-002.md)).

### ASR-2: credenciais e sessões num único ponto, substituível

**Cenário**: (a) nenhum serviço além do `auth` armazena senha ou decide se uma
sessão é válida; (b) depois de um logout, o token deixa de ser aceito
**na requisição seguinte** em qualquer serviço; (c) trocar o mecanismo de
autenticação (por exemplo, pelo login institucional da universidade) deve
exigir mudanças apenas no `auth` e nos adaptadores que o chamam
(`Users.Auth` em Elixir, `auth.zig` em Zig e `authenticate` no `signups`), sem tocar em regras de eventos ou
de contas.

**Por que influencia a arquitetura**: obriga a isolar a autenticação num
componente próprio, a usar token opaco validado a cada requisição em vez de um
token autocontido ([ADR-003](adr/ADR-003.md)) e a acessar o `auth` sempre por
um adaptador dentro de cada serviço (padrão *Gateway*).

### ASR-3: falha do `auth` não derruba os outros serviços

**Cenário**: com o `auth` fora do ar, uma requisição a `users`,
`event_registration` ou `signups` deve ser respondida com **503** e mensagem de erro em
**no máximo 5 segundos**, sem derrubar o processo nem deixar dados pela metade.
Em particular, uma conta não pode ficar criada em `users` sem a credencial
correspondente em `auth`.

**Por que influencia a arquitetura**: como a comunicação é síncrona
([ADR-004](adr/ADR-004.md)), cada chamada ao `auth` precisa de tempo limite e de
tratamento explícito de falha (`{:error, :auth_unavailable}` em Elixir,
`Result.unavailable` em Zig, cliente HTTP com `Timeout` de 5 s no `signups`). A criação de conta grava o nome dentro de uma
transação que é desfeita se o `auth` falhar, o que substitui uma transação
distribuída.

Observação: o `signups` já impede inscrição repetida mesmo com pedidos
simultâneos, com a restrição `UNIQUE (event_id, username)` no banco e uma única
conexão aberta. Quando os eventos tiverem vagas, o requisito "nunca aceitar
mais inscrições do que vagas, mesmo com pedidos simultâneos" deve virar um
quarto ASR. Ele decide onde fica o controle de concorrência: as vagas são do
`event_registration`, mas a contagem de inscritos é do `signups`.
