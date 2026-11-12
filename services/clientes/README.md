# clientes

Cadastro de clientes e endereços. FastAPI + SQLAlchemy 2 + Alembic, em PostgreSQL no schema `clientes`.

## Rodando

Da raiz do repositório, com o `.env` criado a partir do `.env.example`:

```bash
make db-up              # PostgreSQL local
make clientes-migrate   # cria/atualiza as tabelas
make clientes-run       # API em http://localhost:8001/docs
make clientes-test      # testes
```

## Endpoints

| Método | Rota | Sucesso | Erros |
| --- | --- | --- | --- |
| `GET` | `/clientes?limit=20&offset=0` | 200 | 422 |
| `GET` | `/clientes/{id}` | 200 | 404 |
| `POST` | `/clientes` | 201 + `Location` | 422 |
| `PUT` | `/clientes/{id}` | 200 | 404, 422 |
| `DELETE` | `/clientes/{id}` | 204 | 404 |

A listagem é paginada e limitada a 100 itens por chamada. O `PUT` substitui o recurso inteiro: campo opcional omitido volta a ser nulo.

## Estrutura

```
app/
  config.py   configuração por variável de ambiente (pydantic-settings)
  db.py       engine, sessão e schema do serviço
  models.py   tabelas
  schemas.py  formato de entrada e saída da API (Pydantic)
  routers/    rotas por recurso
  main.py     aplicação FastAPI
migrations/   migrations do Alembic, com a tabela de versão no próprio schema
tests/        pytest contra um PostgreSQL real
```

## Testes

Os testes rodam contra o PostgreSQL de verdade, num banco separado (`<POSTGRES_DB>_test`) que é criado e migrado sozinho. Cada teste roda dentro de uma transação desfeita no final, então a ordem não importa e nada vaza de um teste para outro.

## Migrations

A estrutura do banco muda só por migration, nunca à mão.

```bash
cd services/clientes
uv run alembic revision -m "descricao curta"   # nova migration
uv run alembic check                            # confere se o modelo e o banco batem
```
