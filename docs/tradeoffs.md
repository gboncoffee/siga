# Alternativas, trade-offs e evolução

## Alternativas consideradas

**A. Monolito simples**: uma aplicação só, numa linguagem, com um banco e sem
separação interna rígida entre contas, autenticação e eventos.

**B. Monolito modular**: uma aplicação só, numa linguagem, com módulos
`identidade`, `contas`, `eventos` e `inscrições` que só se comunicam por
interfaces públicas. Um banco com tabelas separadas por módulo.

**C. Microsserviços por assunto (escolhida)**: `auth`, `users`,
`event_registration` e `signups` como processos separados, cada um com seu
banco, falando HTTP/JSON.

## Comparação

| Atributo | A. Monolito simples | B. Monolito modular | C. Microsserviços |
|---|---|---|---|
| Modificabilidade | Baixa: sem fronteiras, mudanças se espalham | Boa, se as fronteiras forem respeitadas (nada impede atalhos) | Boa: a fronteira é imposta pelo processo e pelo contrato HTTP |
| Desempenho | Melhor: chamadas em memória | Igual ao A | Pior: cada requisição de eventos ou inscrições faz uma ida extra ao `auth`, e a inscrição mais uma ao `event_registration` (latência de rede local, cerca de 1 ms cada) |
| Disponibilidade | Uma falha derruba tudo | Uma falha derruba tudo | Falha isolada, mas o `auth` é ponto único: sem ele nenhuma rota autenticada funciona |
| Testabilidade | Fácil de subir, difícil isolar partes | Boa: módulos testados com dublês | Boa por serviço (ex.: *stub* do `auth` no `users`). Teste ponta a ponta exige subir 4 processos. |
| Complexidade | Baixa | Média | Alta: três linguagens, quatro *builds*, consistência entre bancos tratada à mão |
| Implantação | Um artefato | Um artefato | Quatro artefatos e configuração de URLs (`SIGA_AUTH_URL`, `-auth-url`, `-event-url`) |
| Escalabilidade | Só a aplicação inteira | Só a aplicação inteira | Por serviço: dá para replicar só eventos/inscrições na semana acadêmica |
| Custo de desenvolvimento | Baixo no início, cresce com o tempo | Médio | Alto para um sistema deste tamanho |
| Desenvolvimento em paralelo e em linguagens diferentes | Impossível | Impossível | Possível (é a motivação principal) |

## Decisão e relação com os ASRs

Para o tamanho do problema, a alternativa **B** seria a mais barata e quase
sempre a recomendada. A escolha por **C** vem principalmente do **ASR-1** e da
restrição de que cada parte é desenvolvida por uma pessoa diferente, em
linguagem diferente. Um monolito obrigaria todos a usarem a mesma linguagem e o
mesmo ciclo de *build*.

Pesa também a natureza do problema: as funcionalidades do SIGA são bem
distintas entre si (identidade, contas, eventos, inscrições) e quase não
compartilham lógica. Por isso a fronteira forte dos microsserviços custa pouco
em chamadas cruzadas e garante que cada funcionalidade fique separada das
outras. Isso facilita a extensão futura: uma funcionalidade nova, como emissão
de certificados, entra como um serviço novo sobre as APIs existentes, sem
alterar os serviços atuais.

O **ASR-2** é atendido por C e também seria por B: o que importa é isolar a
autenticação atrás de uma interface, e em C a fronteira de processo garante que
nenhum outro serviço leia o banco de credenciais.

O **ASR-3** é um custo introduzido por C. Em A e B não existe "`auth` fora do
ar". Por isso ele precisou de tratamento explícito (tempo limite, 503,
transação desfeita).

O preço aceito está em [ADR-001](adr/ADR-001.md): mais complexidade
operacional, latência extra e o `auth` como ponto único de falha.

## Análise de evolução

> Se uma das principais tecnologias ou integrações utilizadas precisasse ser
> substituída, quais partes do sistema seriam afetadas?

### 1. SQLite → PostgreSQL

| | |
|---|---|
| **Afetado** | Em cada serviço que migrar, só a camada de persistência: `auth/repository/repository.go` (driver e SQL de criação de tabelas), `event_registration/src/repository/repository.zig` (biblioteca `zig-sqlite` trocada por um cliente PostgreSQL), `signups/repository.go` (driver e `ON CONFLICT`, que o PostgreSQL também aceita) e, em `users`, o adaptador do Ecto em `config/*.exs` e `mix.exs`. |
| **Inalterado** | *Handlers*, controladores, `Accounts`, gateways do `auth`, contratos HTTP e os outros serviços. |
| **Ajuda** | Repositório isolado em todos os serviços; banco por serviço ([ADR-002](adr/ADR-002.md)), que permite migrar um serviço de cada vez. Ecto já abstrai o banco no `users`. |
| **Atrapalha** | Em Go e Zig o repositório é uma estrutura concreta com a conexão em variável global, sem interface. A troca é localizada, mas não pode ser testada com um repositório falso. |

### 2. Autenticação própria → login institucional da universidade (OIDC)

| | |
|---|---|
| **Afetado** | O `auth`, que passa a validar tokens do provedor institucional (ou a trocá-los por sessões próprias). O `POST /users` deixa de enviar senha, então mudam `Accounts.create_user/1` e `Users.Auth.create_credentials/2`. O `SessionController`, que repassa a resposta do `auth` sem alterações, também muda. |
| **Inalterado** | Se o `auth` mantiver `GET /{token}`, o `event_registration` e o `signups` não mudam nada. Regras e persistência de eventos e inscrições também ficam como estão. |
| **Ajuda** | ASR-2 e [ADR-003](adr/ADR-003.md): só o `auth` sabe o que é uma credencial, e os outros serviços só perguntam "este token vale?". Os gateways (`Users.Auth`, `auth.zig`) concentram as mudanças do lado dos clientes. |
| **Atrapalha** | O repasse da resposta crua do `auth` pelo `users` vaza o formato do `auth` para o cliente. Se o formato mudar, os clientes mudam junto. |

### 3. Inclusão de um aplicativo mobile

| | |
|---|---|
| **Afetado** | Nenhum serviço precisa mudar para o aplicativo funcionar: ele usaria as mesmas APIs HTTP/JSON e o mesmo token Bearer. Seria preciso pôr na frente um *API gateway* ou *proxy* reverso com TLS, pois hoje cada serviço tem porta própria, e o `auth` continua interno. |
| **Inalterado** | Toda a lógica e a persistência. |
| **Ajuda** | Cliente-servidor com API sem estado de sessão no cliente além do token. Nenhum serviço gera HTML. |
| **Atrapalha** | Sessões sem expiração (risco maior em dispositivo móvel) e respostas com formatos de erro diferentes entre serviços. |

### 4. Aumento grande de carga (semana acadêmica)

| | |
|---|---|
| **Afetado** | O `auth` vira gargalo, pois é consultado em toda requisição de eventos e de inscrições. Cada inscrição também consulta o `event_registration`. SQLite limita a escrita concorrente de inscrições, e o `signups` usa uma única conexão. |
| **Possível resposta** | Cache curto (alguns segundos) de tokens válidos no `event_registration` e no `signups`, que enfraquece a revogação imediata do ASR-2; réplicas de `event_registration`; troca para PostgreSQL (mudança 1). |
| **Ajuda** | Os serviços podem ser escalados separadamente. |
| **Atrapalha** | A validação síncrona por requisição ([ADR-003](adr/ADR-003.md)) e a restrição de rodar tudo numa máquina ([ADR-005](adr/ADR-005.md)). |
