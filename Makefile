-include .env
export

POSTGRES_PORT ?= 5432
DB_CONTAINER  := vitrine-db
DB_IMAGE      := postgres:17-alpine

.PHONY: help db-up db-down db-reset db-psql db-bootstrap clientes-migrate clientes-run clientes-test \
	catalogo-migrate catalogo-run catalogo-test pedidos-migrate pedidos-run pedidos-test \
	test migrations-check clientes-migrations-check catalogo-migrations-check \
	pedidos-migrations-check up down logs ps smoke seed \
	lab-deps lab-vm lab-ping lab-ssh lab-destroy lab lab-play lab-idempotencia lab-lint \
	lab-monitoracao lab-monitoracao-down

help: ## Lista os comandos disponíveis
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk -F':.*## ' '{printf "  %-26s %s\n", $$1, $$2}'

# --- ambiente completo em containers (compose.yaml) ---

up: ## Sobe banco + 3 serviços em containers e espera ficarem saudáveis
	@test -f .env || (echo "Crie o .env a partir do .env.example" && exit 1)
	docker compose up -d --build --wait

down: ## Para o ambiente do compose (os dados ficam no volume)
	docker compose down

logs: ## Acompanha os logs dos 3 serviços
	docker compose logs -f clientes catalogo pedidos

ps: ## Situação de cada container do compose
	docker compose ps -a

smoke: ## Confere o ambiente no ar: serviços prontos e um pedido de ponta a ponta
	uv run --no-project --python 3.12 scripts/smoke.py

seed: ## Popula dados de exemplo pelas APIs (pode rodar quantas vezes quiser)
	uv run --no-project --python 3.12 scripts/seed.py $(ARGS)

# --- desenvolvimento local, serviço a serviço ---

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

# --- laboratório Linux (Fase 2): VM no Lima configurada pelo Ansible ---

LAB_VM    := vitrine-lab
LAB_DISCO := vitrine-lab-dados

lab-deps: ## Instala as coleções do Ansible fixadas em lab/requirements.yml
	cd lab && ansible-galaxy collection install -r requirements.yml -p .gerado/colecoes

lab-vm: ## Cria e liga a VM do laboratório (Ubuntu, Lima) e gera o inventário
	@limactl disk list --json 2>/dev/null | grep -q '"$(LAB_DISCO)"' \
		|| limactl disk create $(LAB_DISCO) --size 2GiB --format raw
	@estado="$$(limactl list --format '{{.Status}}' $(LAB_VM) 2>/dev/null)"; \
	case "$$estado" in \
		Running) echo "VM $(LAB_VM) já está ligada" ;; \
		Stopped) limactl start --tty=false $(LAB_VM) ;; \
		*) limactl start --name=$(LAB_VM) --tty=false lab/vm.yaml ;; \
	esac
	lab/inventario.sh
	@# chave do usuário deploy: gerada uma vez no Mac, sobrevive à recriação da VM
	@test -f lab/.gerado/deploy_ed25519 \
		|| ssh-keygen -q -t ed25519 -N "" -C deploy@vitrine-lab -f lab/.gerado/deploy_ed25519

lab: lab-deps lab-vm lab-play lab-monitoracao ## Cria a VM, configura pelo Ansible e liga a monitoração

lab-monitoracao: ## Prometheus, blackbox e Grafana (localhost:3000) monitorando a VM
	docker compose -f lab/monitoracao/compose.yaml up -d --wait

lab-monitoracao-down: ## Desliga a monitoração do laboratório
	docker compose -f lab/monitoracao/compose.yaml down

lab-play: ## Roda o playbook do laboratório na VM
	cd lab && ansible-playbook site.yml

# Roda o playbook de novo e falha se a segunda execução mudar alguma coisa.
lab-idempotencia: ## Confere que rodar o playbook de novo não muda nada
	@# sem tee: com ele, o código de erro do ansible-playbook se perderia
	cd lab && { ansible-playbook site.yml > .gerado/segunda-execucao.log 2>&1; \
		codigo=$$?; cat .gerado/segunda-execucao.log; exit $$codigo; }
	@# exige tarefas executadas: "changed=0" com "unreachable=1" não prova nada
	@grep -qE 'ok=[1-9][0-9]* +changed=0 +unreachable=0 +failed=0' lab/.gerado/segunda-execucao.log \
		&& echo "idempotente: nenhuma mudança na segunda execução" \
		|| { echo "NÃO idempotente: a segunda execução mudou algo"; exit 1; }

lab-lint: ## ansible-lint no perfil production
	cd lab && ansible-lint

lab-ping: ## Confere se o Ansible alcança a VM
	cd lab && ansible all -m ping

lab-ssh: ## Abre um shell na VM
	limactl shell $(LAB_VM)

lab-destroy: ## Apaga a VM, o disco extra e os arquivos gerados
	-limactl delete --force $(LAB_VM)
	-limactl disk delete $(LAB_DISCO)
	rm -f lab/.gerado/inventario.ini lab/.gerado/known_hosts
