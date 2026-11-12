-include .env
export

POSTGRES_PORT ?= 5432
DB_CONTAINER  := vitrine-db
DB_IMAGE      := postgres:17-alpine

.PHONY: help db-up db-down db-reset db-psql clientes-migrate clientes-run clientes-test \
	catalogo-migrate catalogo-run catalogo-test pedidos-migrate pedidos-run pedidos-test

help: ## Lista os comandos disponíveis
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

db-up: ## Sobe o PostgreSQL local
	@test -f .env || (echo "Crie o .env a partir do .env.example" && exit 1)
	docker run -d --name $(DB_CONTAINER) --env-file .env \
		-p 127.0.0.1:$(POSTGRES_PORT):5432 \
		-v vitrine-db-data:/var/lib/postgresql/data \
		$(DB_IMAGE)

db-down: ## Para e remove o container (os dados ficam no volume)
	docker rm -f $(DB_CONTAINER)

db-reset: db-down ## Apaga o volume e recria o banco do zero
	docker volume rm vitrine-db-data
	$(MAKE) db-up

db-psql: ## Abre o psql dentro do container
	docker exec -it $(DB_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

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
