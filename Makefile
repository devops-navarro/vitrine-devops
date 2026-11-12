-include .env
export

POSTGRES_PORT ?= 5432
DB_CONTAINER  := vitrine-db
DB_IMAGE      := postgres:17-alpine

.PHONY: help db-up db-down db-reset db-psql db-bootstrap clientes-migrate clientes-run clientes-test \
	catalogo-migrate catalogo-run catalogo-test pedidos-migrate pedidos-run pedidos-test \
	test migrations-check clientes-migrations-check catalogo-migrations-check \
	pedidos-migrations-check

help: ## Lista os comandos disponíveis
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk -F':.*## ' '{printf "  %-26s %s\n", $$1, $$2}'

# O container recebe só as variáveis do administrador, não as chaves dos serviços.
db-up: ## Sobe o PostgreSQL local
	@test -f .env || (echo "Crie o .env a partir do .env.example" && exit 1)
	docker run -d --name $(DB_CONTAINER) -e POSTGRES_USER -e POSTGRES_PASSWORD -e POSTGRES_DB \
		-p 127.0.0.1:$(POSTGRES_PORT):5432 \
		-v vitrine-db-data:/var/lib/postgresql/data \
		$(DB_IMAGE)

db-down: ## Para e remove o container (os dados ficam no volume)
	docker rm -f $(DB_CONTAINER)

db-reset: db-down ## Apaga o volume e recria o banco do zero
	docker volume rm vitrine-db-data
	$(MAKE) db-up

db-bootstrap: ## Cria um usuário por serviço, dono só do próprio schema
	docker cp infra/postgres/. $(DB_CONTAINER):/tmp/bootstrap
	docker exec -e POSTGRES_DB -e CLIENTES_DB_PASSWORD -e CATALOGO_DB_PASSWORD \
		-e PEDIDOS_DB_PASSWORD $(DB_CONTAINER) \
		psql -q -U $(POSTGRES_USER) -d postgres -f /tmp/bootstrap/bootstrap.sql

db-psql: ## Abre o psql dentro do container
	docker exec -it $(DB_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

# Cada serviço conecta com o próprio usuário, não com o administrador do banco.
# Exportado por alvo para a senha não aparecer no comando que o make imprime.
clientes-%: export POSTGRES_USER = clientes
clientes-%: export POSTGRES_PASSWORD = $(CLIENTES_DB_PASSWORD)
catalogo-%: export POSTGRES_USER = catalogo
catalogo-%: export POSTGRES_PASSWORD = $(CATALOGO_DB_PASSWORD)
pedidos-%: export POSTGRES_USER = pedidos
pedidos-%: export POSTGRES_PASSWORD = $(PEDIDOS_DB_PASSWORD)

clientes-migrate: ## Aplica as migrations do serviço clientes
	cd services/clientes && uv run alembic upgrade head

clientes-run: ## Sobe a API de clientes em http://localhost:8001/docs
	cd services/clientes && uv run uvicorn app.main:app --reload --port 8001

clientes-test: ## Roda os testes do serviço clientes
	cd services/clientes && uv run pytest -q

catalogo-migrate: ## Aplica as migrations do serviço catalogo
	cd services/catalogo && uv run alembic upgrade head

catalogo-run: ## Sobe a API de catálogo em http://localhost:8002/docs
	cd services/catalogo && uv run uvicorn app.main:app --reload --port 8002

catalogo-test: ## Roda os testes do serviço catalogo
	cd services/catalogo && uv run pytest -q

pedidos-migrate: ## Aplica as migrations do serviço pedidos
	cd services/pedidos && uv run alembic upgrade head

pedidos-run: ## Sobe a API de pedidos em http://localhost:8003/docs
	cd services/pedidos && uv run uvicorn app.main:app --reload --port 8003

pedidos-test: ## Roda os testes do serviço pedidos
	cd services/pedidos && uv run pytest -q

test: clientes-test catalogo-test pedidos-test ## Roda os testes dos três serviços

migrations-check: clientes-migrations-check catalogo-migrations-check pedidos-migrations-check ## Confere as migrations dos três serviços

# Aplica, desfaz tudo e reaplica: prova que o downgrade funciona e que as
# migrations sobem num banco vazio. O check falha se o modelo divergir delas.
# Roda no banco de teste, porque o downgrade apaga as tabelas.
MIGRATIONS_CHECK = export POSTGRES_DB=$(POSTGRES_DB)_test \
	&& uv run alembic upgrade head && uv run alembic downgrade base \
	&& uv run alembic upgrade head && uv run alembic check

clientes-migrations-check: ## Confere as migrations do clientes
	cd services/clientes && $(MIGRATIONS_CHECK)

catalogo-migrations-check: ## Confere as migrations do catalogo
	cd services/catalogo && $(MIGRATIONS_CHECK)

pedidos-migrations-check: ## Confere as migrations do pedidos
	cd services/pedidos && $(MIGRATIONS_CHECK)
