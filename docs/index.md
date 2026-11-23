# SIGA - Sistema Interativo de Gestão de Atividades

Documentação do trabalho final de Design e Arquitetura de Software. Tema:
eventos acadêmicos e inscrições.

O SIGA organiza eventos acadêmicos: organizadores cadastram eventos e a
comunidade se inscreve, cancela inscrições e tem a presença registrada. O
sistema é dividido em microsserviços independentes, cada um em uma linguagem:

| Serviço | Linguagem | Função |
|---|---|---|
| `auth` | Go | Credenciais e sessões |
| `users` | Elixir/Phoenix | Contas e login |
| `event_registration` | Zig | Eventos |
| `signups` | Go | Inscrições e presença |

## Conteúdo

- [Requisitos e ASRs](requisitos.md): contexto, atores, requisitos funcionais,
  restrições e os três requisitos arquiteturalmente significativos.
- [Modelo de domínio](dominio.md): conceitos, responsabilidades, GRASP,
  coesão, acoplamento e SOLID.
- [Arquitetura](arquitetura.md): componentes, comunicação, interfaces,
  persistência, segurança e documentação de API.
- [Alternativas e trade-offs](tradeoffs.md): comparação com monolito simples e
  modular, e análise de evolução.
- [Roteiro de demonstração](demonstracao.md): sequência de chamadas `curl`
  que passa por todos os serviços, incluindo os erros e a queda do `auth`.
- [Diagramas UML](diagramas.md): classes, sequência (cadastrar evento, criar
  conta, inscrever em evento), comunicação e componentes.
- Decisões arquiteturais:
  - [ADR-001: Microsserviços por assunto](adr/ADR-001.md)
  - [ADR-002: Um banco SQLite por serviço](adr/ADR-002.md)
  - [ADR-003: Token opaco validado a cada requisição](adr/ADR-003.md)
  - [ADR-004: Comunicação síncrona HTTP/JSON](adr/ADR-004.md)
  - [ADR-005: `auth` acessível só pela máquina local](adr/ADR-005.md)
