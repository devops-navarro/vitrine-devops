-include .env
export

POSTGRES_PORT ?= 5432
# Um só download do provider AWS (~730 MB) para todos os módulos: sem isto,
# cada pasta .terraform guarda a própria cópia.
TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache
DB_CONTAINER  := vitrine-db
DB_IMAGE      := postgres:17-alpine

.PHONY: help db-up db-down db-reset db-psql db-bootstrap clientes-migrate clientes-run clientes-test \
	catalogo-migrate catalogo-run catalogo-test pedidos-migrate pedidos-run pedidos-test \
	test migrations-check clientes-migrations-check catalogo-migrations-check \
	pedidos-migrations-check up down logs ps smoke seed \
	lab-deps lab-vm lab-ping lab-ssh lab-destroy lab lab-play lab-idempotencia lab-lint \
	lab-monitoracao lab-monitoracao-down scripts-lint scripts-test \
	tf-fmt tf-validate tf-lint tf-sec tf-test tf-check \
	tf-local-up tf-local-apply tf-local-plan tf-local-destroy tf-local-down \
	k8s-up k8s-down k8s-status k8s-lint k8s-banco k8s-imagens k8s-servicos k8s-app k8s-smoke k8s-seed

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

# --- scripts Bash ---

scripts-lint: ## shellcheck nos scripts Bash
	shellcheck scripts/*.sh lab/*.sh

scripts-test: ## Testes dos scripts Bash (bats)
	bats scripts/testes/

# --- Terraform (Fase 3): tudo roda sem conta AWS ---

TF_RAIZES := $(sort $(wildcard infra/modules/*) $(filter-out infra/envs/local,$(wildcard infra/envs/*)) $(patsubst %/main.tf,%,$(wildcard infra/envs/local/*/main.tf)))
TF_MODULOS_COM_TESTE := $(sort $(patsubst %/tests,%,$(wildcard infra/modules/*/tests)))

tf-fmt: ## terraform fmt (só confere, não altera)
	terraform fmt -check -recursive -diff infra

tf-validate: ## terraform validate em cada módulo e ambiente, sem backend
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@for d in $(TF_RAIZES); do \
		echo "== $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d validate -no-color || exit 1; \
	done

tf-lint: ## tflint com o plugin AWS
	cd infra && tflint --init && tflint --recursive --config "$$PWD/.tflint.hcl"

tf-sec: ## Checkov: configurações inseguras
	checkov -d infra --framework terraform --quiet --compact

tf-test: ## terraform test com provider simulado (sem credenciais)
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@for d in $(TF_MODULOS_COM_TESTE); do \
		echo "== $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d test -no-color || exit 1; \
	done

tf-check: tf-fmt tf-validate tf-lint tf-sec tf-test ## Todos os checks de Terraform

# --- Terraform contra o emulador (Moto): plan, apply e destroy sem conta AWS ---

TF_LOCAL := infra/envs/local
# Rede de segurança: qualquer serviço que faltar na lista de endpoints vai para
# o emulador, nunca para a AWS de verdade.
tf-local-%: export AWS_ENDPOINT_URL = https://localhost:4566

tf-local-up: ## Sobe o emulador da AWS (Moto) em https://localhost:4566
	docker compose -f $(TF_LOCAL)/compose.yaml up -d --wait

tf-local-apply: ## Aplica no emulador: bucket do state e depois rede, ECR e OIDC com state remoto
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	terraform -chdir=$(TF_LOCAL)/bootstrap init -input=false
	terraform -chdir=$(TF_LOCAL)/bootstrap apply -auto-approve -input=false
	terraform -chdir=$(TF_LOCAL)/plataforma init -reconfigure -input=false
	terraform -chdir=$(TF_LOCAL)/plataforma apply -auto-approve -input=false

tf-local-plan: ## Plan da plataforma no emulador; falha se houver mudança pendente
	terraform -chdir=$(TF_LOCAL)/plataforma plan -detailed-exitcode -input=false

tf-local-destroy: ## Destroi a plataforma no emulador (o bucket do state fica: force_destroy = false)
	terraform -chdir=$(TF_LOCAL)/plataforma destroy -auto-approve -input=false

tf-local-down: ## Desliga o emulador (que zera tudo) e apaga o state e o cache locais
	docker compose -f $(TF_LOCAL)/compose.yaml down
	rm -f $(TF_LOCAL)/bootstrap/terraform.tfstate $(TF_LOCAL)/bootstrap/terraform.tfstate.backup
	@# a configuração de backend guardada aqui apontaria para um emulador desligado
	rm -rf $(TF_LOCAL)/bootstrap/.terraform $(TF_LOCAL)/plataforma/.terraform

# --- Kubernetes local (Fase 4): kind com a mesma versão do EKS ---

K8S_CLUSTER  := vitrine
K8S_CONTEXTO := kind-$(K8S_CLUSTER)
TRAEFIK_CHART := 42.4.0
METRICS_CHART := 3.13.1

k8s-up: ## Cria o cluster kind com ingress (Traefik) e metrics-server
	@kind get clusters 2>/dev/null | grep -qx $(K8S_CLUSTER) \
		|| kind create cluster --config deploy/kind/cluster.yaml --wait 120s
	helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update >/dev/null
	helm --kube-context $(K8S_CONTEXTO) upgrade --install traefik traefik/traefik \
		--version $(TRAEFIK_CHART) --namespace traefik --create-namespace \
		--values deploy/plataforma/traefik.yaml --wait
	helm --kube-context $(K8S_CONTEXTO) upgrade --install metrics-server metrics-server/metrics-server \
		--version $(METRICS_CHART) --namespace kube-system \
		--values deploy/plataforma/metrics-server.yaml --wait

k8s-status: ## Nós, pods de todos os namespaces e uso de recursos
	kubectl --context $(K8S_CONTEXTO) get nodes -o wide
	kubectl --context $(K8S_CONTEXTO) get pods -A
	-kubectl --context $(K8S_CONTEXTO) top nodes

k8s-down: ## Apaga o cluster kind
	kind delete cluster --name $(K8S_CLUSTER)

SERVICOS := clientes catalogo pedidos
K8S_RENDER := deploy/renderizado

# Renderiza o chart de cada serviço e valida: helm lint, esquema do Kubernetes
# (kubeconform), configuração insegura (Trivy e Checkov).
k8s-lint: ## Valida o chart Helm de cada serviço
	@mkdir -p $(K8S_RENDER)
	@for s in $(SERVICOS); do \
		helm lint deploy/charts/servico -f deploy/servicos/$$s.yaml --set imagem.tag=validacao --strict >/dev/null || exit 1; \
		helm template $$s deploy/charts/servico -f deploy/servicos/$$s.yaml \
			--set imagem.tag=validacao --namespace vitrine > $(K8S_RENDER)/$$s.yaml || exit 1; \
	done
	@cp deploy/banco/*.yaml $(K8S_RENDER)/
	kubeconform -strict -summary -kubernetes-version 1.35.0 $(K8S_RENDER)
	trivy config --quiet --severity MEDIUM,HIGH,CRITICAL --exit-code 1 \
		--ignorefile deploy/.trivyignore.yaml $(K8S_RENDER)
	checkov -d $(K8S_RENDER) --framework kubernetes --quiet --compact

K8S := kubectl --context $(K8S_CONTEXTO)
# Tag da imagem = commit; "-sujo" se houver mudança não commitada, para nunca
# confundir o que está rodando com o que está no Git.
IMAGEM_TAG ?= $(shell git rev-parse --short HEAD)$(shell git diff --quiet HEAD 2>/dev/null || echo -sujo)

k8s-banco: ## Namespace, segredos a partir do .env, PostgreSQL e bootstrap dos usuários
	@test -f .env || (echo "Crie o .env a partir do .env.example" && exit 1)
	$(K8S) apply -f deploy/banco/namespace.yaml
	@# segredos gerados na hora a partir do .env: nunca gravados em arquivo
	@$(K8S) -n vitrine create secret generic vitrine-banco \
		--from-literal=admin-usuario="$$POSTGRES_USER" \
		--from-literal=admin-senha="$$POSTGRES_PASSWORD" \
		--from-literal=clientes-senha="$$CLIENTES_DB_PASSWORD" \
		--from-literal=catalogo-senha="$$CATALOGO_DB_PASSWORD" \
		--from-literal=pedidos-senha="$$PEDIDOS_DB_PASSWORD" \
		--dry-run=client -o yaml | $(K8S) apply -f -
	@$(K8S) -n vitrine create secret generic vitrine-api \
		--from-literal=api-keys="$$API_KEYS" \
		--from-literal=chave-interna="$${API_KEYS%%,*}" \
		--dry-run=client -o yaml | $(K8S) apply -f -
	$(K8S) -n vitrine create configmap banco-bootstrap-sql --from-file=infra/postgres \
		--dry-run=client -o yaml | $(K8S) apply -f -
	$(K8S) apply -f deploy/banco/postgres.yaml
	$(K8S) -n vitrine rollout status statefulset/postgres --timeout=180s
	$(K8S) -n vitrine delete job banco-bootstrap --ignore-not-found
	$(K8S) apply -f deploy/banco/bootstrap.yaml
	$(K8S) -n vitrine wait --for=condition=complete job/banco-bootstrap --timeout=180s

k8s-imagens: ## Constrói as imagens com a tag do commit e carrega no kind
	@for s in $(SERVICOS); do \
		docker build -q -t vitrine/$$s:$(IMAGEM_TAG) services/$$s >/dev/null || exit 1; \
		kind load docker-image vitrine/$$s:$(IMAGEM_TAG) --name $(K8S_CLUSTER) || exit 1; \
	done

k8s-servicos: k8s-imagens ## Instala ou atualiza os três serviços pelo chart
	@for s in $(SERVICOS); do \
		echo "== $$s ($(IMAGEM_TAG))"; \
		helm --kube-context $(K8S_CONTEXTO) upgrade --install $$s deploy/charts/servico \
			--namespace vitrine -f deploy/servicos/$$s.yaml \
			--set imagem.repositorio=vitrine/$$s --set imagem.tag=$(IMAGEM_TAG) \
			--set imagem.politicaPull=Never --wait --timeout 5m || exit 1; \
	done

k8s-app: k8s-banco k8s-servicos ## Banco e serviços no cluster local

# Pelo ingress, um endereço só: o roteamento é pelo prefixo do caminho.
K8S_INGRESS := http://127.0.0.1:8080

k8s-smoke: ## Smoke test pelo ingress do cluster local
	SMOKE_VIA_INGRESS=1 SMOKE_CLIENTES_URL=$(K8S_INGRESS) SMOKE_CATALOGO_URL=$(K8S_INGRESS) \
		SMOKE_PEDIDOS_URL=$(K8S_INGRESS) uv run --no-project --python 3.12 scripts/smoke.py

k8s-seed: ## Dados de exemplo pelo ingress do cluster local
	SEED_CLIENTES_URL=$(K8S_INGRESS) SEED_CATALOGO_URL=$(K8S_INGRESS) SEED_PEDIDOS_URL=$(K8S_INGRESS) \
		uv run --no-project --python 3.12 scripts/seed.py $(ARGS)
