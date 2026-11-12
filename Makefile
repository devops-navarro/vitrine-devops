-include .env
export

POSTGRES_PORT ?= 5432
DB_CONTAINER  := vitrine-db
DB_IMAGE      := postgres:17-alpine

.PHONY: help db-up db-down db-reset db-psql

help: ## Lista os comandos disponíveis
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

db-up: ## Sobe o PostgreSQL local (aplica os SQLs na primeira vez)
	@test -f .env || (echo "Crie o .env a partir do .env.example" && exit 1)
	docker run -d --name $(DB_CONTAINER) --env-file .env \
		-p 127.0.0.1:$(POSTGRES_PORT):5432 \
		-v vitrine-db-data:/var/lib/postgresql/data \
		-v $(CURDIR)/services/clientes/sql:/docker-entrypoint-initdb.d:ro \
		$(DB_IMAGE)

db-down: ## Para e remove o container (os dados ficam no volume)
	docker rm -f $(DB_CONTAINER)

db-reset: db-down ## Apaga o volume e recria o banco do zero
	docker volume rm vitrine-db-data
	$(MAKE) db-up

db-psql: ## Abre o psql dentro do container
	docker exec -it $(DB_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)
