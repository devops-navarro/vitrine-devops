# Vitrine · DevOps portfolio

> 🇧🇷 Mini e-commerce com 3 microsserviços em Kubernetes na AWS, com infraestrutura em Terraform, entrega via GitHub Actions + Argo CD e observabilidade completa (métricas, logs, traces e SLO).
>
> 🇺🇸 A 3-service e-commerce running on Kubernetes (AWS EKS), provisioned with Terraform, delivered through GitHub Actions + Argo CD, and fully observable (metrics, logs, traces, SLOs).

[![ci](https://github.com/devops-navarro/vitrine-devops/actions/workflows/ci.yml/badge.svg)](https://github.com/devops-navarro/vitrine-devops/actions/workflows/ci.yml)

**Status:** Fase 1 · em construção

## Arquitetura alvo · Target architecture

```mermaid
flowchart LR
  dev[PR no GitHub] --> gha[GitHub Actions<br/>lint · testes · scan · build]
  gha -->|imagem| ecr[(Amazon ECR)]
  gha -->|atualiza values| git[deploy/ no Git]
  git --> argo[Argo CD]
  subgraph aws[AWS · Terraform]
    subgraph eks[EKS]
      argo --> apps
      subgraph apps[namespace vitrine]
        pedidos[pedidos] --> clientes[clientes]
        pedidos --> catalogo[catalogo]
        clientes --> pg[(PostgreSQL)]
        catalogo --> pg
        pedidos --> pg
      end
      apps -. métricas · logs · traces .-> obs[Prometheus · Grafana · Loki · Tempo]
    end
  end
  obs --> chat[Alertas no Slack/Discord]
```

## Stack

| Camada | Ferramentas |
| --- | --- |
| Aplicação | Python 3.12, FastAPI, PostgreSQL, pytest |
| Infraestrutura | AWS (VPC, EKS, ECR, IAM, Secrets Manager), Terraform |
| Entrega | Docker, Helm, GitHub Actions (OIDC), Argo CD |
| Observabilidade | Prometheus, Alertmanager, Grafana, Loki, OpenTelemetry, Tempo, k6 |
| Segurança | gitleaks, Trivy, Checkov, External Secrets, Pod Security Standards |
| Automação | Ansible, Bash, Make |

A escolha da stack segue o que as vagas DevOps remotas pedem: veja [ADR 0000](docs/adr/0000-stack-e-forma-de-trabalho.md).

## Roadmap

Cada fase é um [milestone](https://github.com/devops-navarro/vitrine-devops/milestones) com suas issues.

- [ ] **Fase 1** · APIs FastAPI + PostgreSQL (`services/`, `scripts/`)
- [ ] **Fase 2** · Linux, redes e automação com Ansible (`lab/`, `scripts/`)
- [ ] **Fase 3** · AWS com Terraform (`infra/`)
- [ ] **Fase 4** · Containers, Kubernetes, CI/CD e GitOps (`deploy/`, `.github/`)
- [ ] **Fase 5** · Certificação AWS e inglês (em paralelo às Fases 3 e 4)
- [ ] **Fase 6** · Observabilidade e SRE (`observability/`, `loadtest/`)
- [ ] **Fase 7** · Segurança e acabamento (`docs/`)

## Estrutura

```
services/        microsserviços (clientes, catalogo, pedidos)
scripts/         automação em Python e Bash
lab/             VM Linux + Ansible (Fase 2)
infra/           Terraform: bootstrap do state, módulos e ambientes
deploy/          chart Helm e aplicações do Argo CD
observability/   dashboards, alertas e values da stack de monitoração
loadtest/        testes de carga com k6
docs/            ADRs, runbooks, post-mortems, evidências e diário
```

## Como trabalho neste repositório

- **Branch por tarefa e merge por PR.** A `main` é protegida e só recebe código com o CI verde.
- **[Conventional Commits](https://www.conventionalcommits.org/pt-br/):** `feat:`, `fix:`, `docs:`, `ci:`, `infra:`, `test:`, `chore:`.
- **Decisões registradas** em [`docs/adr/`](docs/adr/) e **diário de bordo** em [`docs/diario.md`](docs/diario.md).
- **Fim de fase** = tag de versão (`v0.N.0`) + evidências em `docs/evidencias/fase-N/`.

## Regras

1. Nenhum segredo no Git. Segredos ficam no Secrets Manager ou num `.env` local listado no `.gitignore`. O `gitleaks` roda no pre-commit e no CI.
2. Toda infraestrutura nasce de código: nada criado à mão no console.
3. Recursos na AWS levam as tags `projeto=vitrine`, `owner` e `ttl`, e são destruídos no fim de cada sessão (`make aws-down`).

## Rodando os checks localmente

```bash
pipx install pre-commit   # ou: pip install pre-commit
pre-commit install
pre-commit run --all-files
```

## Licença

[MIT](LICENSE)
