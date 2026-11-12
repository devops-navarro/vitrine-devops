# Diário de bordo

O que fiz, o que travou e como resolvi.

## Configuração do repositório

- Criei a conta GitHub do projeto e o repositório.
- Configurei o repositório com proteção da `main`, CI com pre-commit (gitleaks, ruff), templates de PR e issue e o roadmap em milestones.
- Próximo: Fase 1, serviço `clientes` com FastAPI e PostgreSQL.

## Fase 1 · serviços

- Três serviços FastAPI (`clientes`, `catalogo`, `pedidos`), cada um com schema, migrations e testes próprios.
- O que travou: marcar um novo endereço principal dava `UniqueViolation` nos testes. A sessão de teste tinha `autoflush` ligado e a da aplicação não; o ORM gravava o novo principal antes de desmarcar o antigo. A fixture passou a usar o mesmo `SessionLocal` da aplicação, e o código desmarca o anterior primeiro.
- Testei a integração do `pedidos` derrubando e travando o catálogo com os três serviços no ar: 503 com `Retry-After`, e no caso travado, resposta no tempo do timeout (3 s).
- O que travou: ao separar um usuário por serviço no banco, as migrations pararam com `permission denied for database`. O `CREATE SCHEMA IF NOT EXISTS` do Alembic exige permissão de criar mesmo quando o schema existe. Criar schema virou tarefa do `make db-bootstrap`, e o serviço só confere se ele existe.
- Achado de segurança: o erro de configuração do pydantic imprimia a senha do banco e a API key no log. Corrigido com `hide_input_in_errors` e teste.
- Fase 1 fechada em `v0.1.0`. O que mais ensinou: os bugs que só apareceram com banco vazio, usuário restrito ou rede de verdade. Teste em ambiente parecido com produção paga o custo.
- Próximo: Fase 2, Linux, redes e automação.

## Fase 2 · Linux, redes e automação

- VM Ubuntu 26.04 no Lima, configurada só pelo Ansible (roles base, web, disco e monitoracao), monitorada com Prometheus, blackbox e Grafana.
- O que travou: depois de um reboot, o SSH recusou a VM com "remote host identification has changed". O Lima gera um instance-id novo a cada partida e o cloud-init regera as chaves do host. Passei a ler as chaves pelo canal local do Lima e a exigir correspondência exata.
- O que travou: o check de idempotência aprovava com a VM fora do ar, porque `changed=0` e `failed=0` também aparecem quando nada roda. Desde então, todo check novo é testado no caso em que deve falhar.
- Fase 2 fechada em `v0.2.0`. Próximo: Fase 3, AWS com Terraform.
