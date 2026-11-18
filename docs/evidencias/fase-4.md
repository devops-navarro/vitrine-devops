# Fase 4 · Containers, Kubernetes, CI/CD e GitOps

Versão `v0.4.0`. Os três serviços em Kubernetes, com imagens construídas e varridas pelo pipeline e o cluster entregue pelo Argo CD a partir do Git. Tudo num cluster local (kind) com a mesma versão do EKS; na AWS mudam o registro e o cluster, não o processo ([ADR 0004](../adr/0004-kubernetes-entrega-e-gitops.md)).

## O que foi entregue

| Entrega | PR |
| --- | --- |
| Cluster kind (Kubernetes 1.35.8 por digest, 3 nós), Traefik e metrics-server | #84 |
| Chart Helm único: probes, segurança `restricted`, HPA, PDB, NetworkPolicy, migrations como hook; `make k8s-lint` no CI | #85 |
| Namespace com Pod Security `restricted`, PostgreSQL, segredos a partir do `.env`, bootstrap | #86 |
| Ingress e smoke/seed pelo cluster | #87 |
| Deploy num kind a cada PR (`k8s-deploy`) | #88 |
| Imagens amd64 e arm64, varridas pelo Trivy, publicadas no GHCR com proveniência e SBOM | #89 |
| GitOps com Argo CD: AppProject, ApplicationSet, versões por ambiente no Git | #90 |
| [ADR 0004](../adr/0004-kubernetes-entrega-e-gitops.md) | #91 |

## Números

| Medida | Resultado |
| --- | --- |
| Cluster local do zero (`make k8s-up`) | ~80 s |
| Argo CD do zero até tudo sincronizado e saudável | menos de 3 min |
| Checks obrigatórios na `main` | 10, mais o workflow `imagens` |
| `k8s-deploy` no CI (cluster, banco, serviços, smoke e seed) | ~3 min |
| `make k8s-lint` | 30 recursos válidos no Kubernetes 1.35; Checkov 692 aprovadas, 0 reprovadas |
| Vulnerabilidades altas ou críticas com correção nas imagens | 0 |

## Comportamentos provados

| Cenário | Resultado | PR |
| --- | --- | --- |
| Pod root no namespace `vitrine` | `Forbidden: violates PodSecurity "restricted:latest"` | #86 |
| Pod de fora tentando o banco e o `clientes` | Bloqueado pelas NetworkPolicies | #86 |
| `pedidos` → `clientes` / `clientes` → `catalogo` | 200 / bloqueado (não precisa) | #86 |
| `/health`, `/metrics`, `/docs` e `/clientes/../metrics` pelo ingress | 404 | #87 |
| `allowPrivilegeEscalation: true` no chart | `make k8s-lint` falha (`KSV-0001`) | #85 |
| Base Python 3.12.0 (2023) numa imagem | Trivy: 90 vulnerabilidades com correção (13 críticas, 77 altas); pipeline vermelho | #89 |
| Imagem publicada | Índice OCI com `linux/amd64`, `linux/arm64` e atestados; pull anônimo funciona | #89 |
| NetworkPolicy apagada à mão (GitOps) | Recriada pelo Argo CD em 31 s | #90 |
| Commit mudando configuração do `clientes` | No cluster em 89 s, sem comando no cluster | #90 |
| `git revert` desse commit | De volta em 100 s | #90 |
| PostgreSQL reiniciado | Dados preservados no volume | #86 |

## Achados no caminho

- Disco da VM do Colima remontado só para leitura depois do disco do Mac encher; `e2fsck` e remontagem limpa (#84).
- Chart 42 do Traefik com esquema de valores novo (#84).
- **Checkov aprovando no vazio**: pasta oculta (`.renderizado`) não é analisada (#85).
- `namespace` duplicado nos templates, pego pelo kubeconform (#85).
- Versão inexistente de action no CI (`setup-trivy@v0.2.3`) (#85).
- Tag de imagem que muda sozinha (`17-alpine`) e pod sem NetworkPolicy, pegos pelo Checkov (#86).
- Argo CD com Ingress `Progressing` para sempre: o status precisa de endereço (#90).
- Atualização do Traefik em impasse com `hostPort` (#90).
- Smoke quebrando no CI com resposta em texto durante a espera (#90).

## Como reproduzir

```bash
cp .env.example .env
make k8s-up && make k8s-gitops    # cluster e Argo CD; banco e serviços vêm do Git
make k8s-argocd-status
make k8s-smoke && make k8s-seed
make k8s-lint
make k8s-down
```
