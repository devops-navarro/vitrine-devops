# catalogo

Catálogo de produtos. FastAPI + SQLAlchemy 2 + Alembic, em PostgreSQL no schema `catalogo`.

Segue os mesmos padrões do serviço `clientes` (configuração, autenticação, testes). O código é copiado, não compartilhado por biblioteca: cada serviço evolui e faz deploy sozinho.

## Rodando

Da raiz do repositório, com o `.env` criado a partir do `.env.example`:

```bash
make db-up              # PostgreSQL local
make catalogo-migrate   # cria/atualiza as tabelas
make catalogo-run       # API em http://localhost:8002/docs
make catalogo-test      # testes
```

## Autenticação

Header `X-API-Key` com uma das chaves de `API_KEYS`. Sem ela, 401. `/health` e `/docs` ficam abertos.

## Endpoints

| Método | Rota | Sucesso | Erros |
| --- | --- | --- | --- |
| `GET` | `/produtos?ativo=true&limit=20&offset=0` | 200 | 422 |
| `GET` | `/produtos/{id}` | 200 | 404 |
| `POST` | `/produtos` | 201 + `Location` | 409, 422 |
| `PUT` | `/produtos/{id}` | 200 | 404, 409, 422 |
| `DELETE` | `/produtos/{id}` | 204 | 404 |

Regras:
- **Preço em centavos, inteiro** (`4990` = R$ 49,90). Float não representa valores como 0,10 com exatidão e acumula erro em somas. A API recusa `49.9` e `"4990"` em vez de converter.
- **SKU** é o código único do produto: letras, números e hífen, gravado em maiúsculas. Repetido devolve 409.
- **`DELETE` desativa** (`ativo = false`), não apaga. O produto sai da venda, mas continua legível por id, porque pedidos antigos apontam para ele.
- A listagem filtra por `ativo` e é paginada, com no máximo 100 itens.

## Estrutura

```
app/
  config.py     configuração por variável de ambiente
  db.py         engine, sessão e schema do serviço
  deps.py       dependências compartilhadas pelas rotas
  models.py     tabelas
  schemas.py    entrada e saída da API
  seguranca.py  API key
  routers/      rotas por recurso
  main.py       aplicação FastAPI
migrations/     Alembic, com a tabela de versão no próprio schema
tests/          pytest contra um PostgreSQL real
```
