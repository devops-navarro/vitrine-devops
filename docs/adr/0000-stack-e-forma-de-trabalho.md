# ADR 0000 · Stack do projeto e forma de trabalho

- **Status:** aceita
- **Data:** 2026-11-11

## Contexto

Este repositório é um portfólio de estudo para vagas DevOps remotas. A stack precisa refletir o que o mercado pede, não preferência pessoal.

Analisei 570 vagas DevOps remotas publicadas no Brasil entre 26/09 e 10/11/2026. Os itens mais citados foram:

| Item | Vagas |
| --- | --- |
| Terraform | 62% |
| AWS | 57% |
| Kubernetes | 53% |
| Python | 48% |
| Docker | 38% |
| Grafana | 24% |
| GitHub Actions | 23% |
| Prometheus | 20% |

Por área: cloud 75%, IaC 68%, CI/CD 65%, Kubernetes 62%, observabilidade 52%, segurança/IAM 38%. Dois terços das vagas pedem 4 ou mais dessas áreas ao mesmo tempo, por isso o projeto integra todas num sistema só em vez de exercícios soltos.

## Decisão

- **Nuvem:** AWS, com EKS. É a nuvem mais pedida e combina com a certificação Solutions Architect Associate.
- **IaC:** Terraform, com módulos e state remoto no S3.
- **Aplicação:** Python com FastAPI e PostgreSQL. Python é a linguagem mais citada e também a de automação.
- **Entrega:** GitHub Actions com OIDC (sem chaves fixas) e Argo CD (GitOps).
- **Observabilidade:** Prometheus, Grafana, Loki e OpenTelemetry com Tempo.
- **Forma de trabalho:** branch e PR para tudo, Conventional Commits, CI desde o primeiro commit, ADR para cada decisão relevante e uma tag de versão por fase.

## Alternativas consideradas

- **Azure ou GCP:** 32% e 21% das vagas. Os conceitos se transferem; AWS cobre mais vagas.
- **ECS em vez de EKS:** mais simples e barato, mas Kubernetes aparece em mais da metade das vagas.
- **GitLab CI ou Jenkins:** também comuns, mas GitHub Actions é o CI mais citado e roda no mesmo lugar do código.

## Consequências

- O EKS custa por hora. O ambiente é criado e destruído a cada sessão (`make aws-up` / `make aws-down`), com AWS Budget como rede de segurança.
- Desenvolvimento e testes acontecem primeiro localmente (Docker Compose e kind), e a AWS entra quando o fluxo local já funciona.
