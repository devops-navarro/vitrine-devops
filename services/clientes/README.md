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

## Estrutura

```
app/
  config.py   configuração por variável de ambiente (pydantic-settings)
  db.py       engine, sessão e schema do serviço
  models.py   tabelas
  main.py     aplicação FastAPI
migrations/   migrations do Alembic, com a tabela de versão no próprio schema
tests/
```

## Migrations

A estrutura do banco muda só por migration, nunca à mão.

```bash
cd services/clientes
uv run alembic revision -m "descricao curta"   # nova migration
uv run alembic check                            # confere se o modelo e o banco batem
```
