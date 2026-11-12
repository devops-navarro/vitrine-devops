# Fase 1 · APIs e banco de dados

Versão `v0.1.0`. Três serviços FastAPI com PostgreSQL, testados no CI contra banco real e empacotados em containers.

## O que foi entregue

| Entrega | PR |
| --- | --- |
| PostgreSQL local e tabela de clientes | #16 |
| Base do serviço `clientes`: FastAPI, SQLAlchemy 2, Alembic, configuração por ambiente | #17 |
| CRUD de clientes com paginação e status HTTP corretos | #18 |
| Validação de CPF (dígito verificador) e e-mail, 409 em duplicado | #19 |
| Endereços do cliente (1:N), com um principal por cliente garantido pelo banco | #20 |
| Autenticação por API key, com rodízio de chave | #21 |
| Serviço `catalogo`: preço em centavos, SKU, soft delete | #22 |
| Serviço `pedidos`: valida cliente e produtos por HTTP, timeout, 502/503, snapshot de preço | #23 |
| [ADR 0001](../adr/0001-um-schema-por-dominio.md): um schema e um usuário de banco por serviço | #24 |
| `/health`, `/ready`, `/metrics` e logs JSON com request id entre serviços | #25 |
| Testes e migrations no CI, cobertura mínima de 70% | #26 |
| Docker Compose com banco, bootstrap, migrations e os 3 serviços | #27 |
| Seed declarativo e idempotente pelas APIs | #28 |
| [Arquitetura](../arquitetura.md) e [ADR 0002](../adr/0002-exposicao-com-alb-e-waf.md) (ALB + WAF) | #29 |

## Números

CI na `main` no commit `6541e80` ([execução](https://github.com/devops-navarro/vitrine-devops/actions/runs/43297693085)), cinco jobs obrigatórios verdes:

| Job | Resultado |
| --- | --- |
| `testes (clientes)` | 117 testes, cobertura 99,22% |
| `testes (catalogo)` | 69 testes, cobertura 98,85% |
| `testes (pedidos)` | 73 testes, cobertura 99,46% |
| `compose` | ambiente sobe do `.env.example`, smoke ok, seed idempotente |
| `pre-commit` | gitleaks, ruff, checks de arquivo |

Cada job de testes também aplica as migrations num banco vazio, desfaz até o zero, reaplica e roda `alembic check`.

## Comportamentos provados com o sistema no ar

| Cenário | Resultado | PR |
| --- | --- | --- |
| Catálogo derrubado durante a criação de pedido | 503 com `Retry-After: 5`; `/health` do pedidos continua 200 | #23 |
| Catálogo aceitando conexão sem responder | 503 em 3,03 s (o timeout configurado) | #23 |
| Preço alterado no catálogo depois da venda | Total do pedido não muda | #23 |
| Serviço tentando ler o schema de outro | `permission denied for schema` | #24 |
| Banco parado | `/ready` 503 em 2 ms, `/health` 200; volta sozinho quando o banco volta | #25 |
| Um pedido com `X-Request-ID` | O mesmo id no log dos três serviços | #25, #27 |
| Processo dentro do container | `uid=10001`, sem permissão de escrita no próprio código | #27 |
| Seed rodado de novo depois de mudanças feitas por fora | Corrige só o que mudou; segunda rodada sem mudanças | #28 |

## Bugs encontrados no caminho

Cada um está descrito no PR onde foi corrigido.

- Índice de e-mail no modelo com `func.lower("email")`, que vira `lower('email')` literal (#17).
- Sessão de teste com `autoflush` diferente da aplicação, escondendo erro de ordem no endereço principal (#20).
- Erro de configuração do pydantic imprimindo senha do banco e API key no log (#21).
- Usuário de banco dos serviços era superusuário; `CREATE SCHEMA IF NOT EXISTS` exigia permissão que o serviço não deve ter (#24).
- `fileConfig` do Alembic desligando em silêncio os loggers da aplicação nos testes (#25).
- Migration desfeita em silêncio (autobegin do SQLAlchemy 2) e `alembic check` cego para o schema do serviço (`search_path`), os dois só visíveis partindo de banco vazio (#26).

## Como reproduzir

```bash
cp .env.example .env
make up && make smoke && make seed
make test && make migrations-check
```
