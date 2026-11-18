# deploy

Tudo o que roda os serviços em Kubernetes. Localmente, num cluster [kind](https://kind.sigs.k8s.io/) com a mesma versão do EKS.

```
deploy/
  kind/cluster.yaml     o cluster local: 1 control plane e 2 workers, Kubernetes 1.35.8 fixado por digest
  plataforma/           o que o cluster precisa antes dos serviços: ingress e métricas
  charts/servico/       chart Helm único, que implanta qualquer um dos três serviços
  servicos/             os valores de cada serviço: só o que muda entre eles
```

## Cluster local

Precisa de Docker (Colima), `kind`, `kubectl` e `helm`.

```bash
make k8s-up       # cria o cluster, instala Traefik e metrics-server (~80 s do zero)
make k8s-status   # nós, pods e uso de recursos
make k8s-down     # apaga o cluster
```

O ingress fica em `http://127.0.0.1:8080`, só acessível pelo próprio Mac.

| Peça | Versão | Por quê |
| --- | --- | --- |
| Kubernetes | 1.35.8 | A mesma do módulo EKS: o que funciona aqui funciona lá |
| Traefik (chart 42.4.0) | v3.7 | Ingress controller local. O ingress-nginx foi aposentado pelo projeto Kubernetes; o recurso `Ingress` continua o padrão e, no EKS, vira ALB pelo AWS Load Balancer Controller (ADR 0002) |
| metrics-server (chart 3.13.1) | 0.8 | CPU e memória dos pods, que o HPA usa para escalar |

Dois workers para que réplicas fiquem em nós diferentes e o PodDisruptionBudget tenha efeito ao drenar um nó.

## Chart `servico`

Um chart para os três serviços. Cada um tem um arquivo em `servicos/` com o que muda: caminhos públicos, quem pode chamar quem e as variáveis. A tag da imagem é obrigatória e não pode ser `latest`: ela é o commit, para sempre se saber o que está rodando.

| Recurso | Decisão |
| --- | --- |
| Deployment | `maxUnavailable: 0` (sobe a nova réplica antes de tirar a antiga), réplicas espalhadas por nós, `preStop` de 5 s para o Service parar de mandar tráfego antes do SIGTERM |
| Probes | `startupProbe` e `livenessProbe` em `/health` (não olha o banco); `readinessProbe` em `/ready` (olha) |
| Segurança | Sem root (uid 10001), sistema de arquivos só leitura (só `/tmp` gravável), sem capabilities, seccomp `RuntimeDefault`, sem escalada de privilégio, sem token da API do Kubernetes montado |
| Recursos | Request de CPU e memória; limite só de memória. Sem limite de CPU para não sofrer throttling com o nó ocioso |
| HPA | 2 a 5 réplicas por CPU (70% do request); sobe rápido, desce depois de 5 minutos estável |
| PodDisruptionBudget | Ao menos 1 réplica de pé durante a manutenção de um nó |
| NetworkPolicy | Nega tudo que não está listado. Entrada: o ingress e, para `clientes` e `catalogo`, o `pedidos`. Saída: DNS, banco e, para o `pedidos`, `clientes` e `catalogo` |
| Migrations | Job de hook do Helm (`pre-install`, `pre-upgrade`): se a migration falhar, o upgrade para e a versão antiga continua no ar |
| Ingress | Só os prefixos de negócio (`/clientes`, `/produtos`, `/pedidos`); `/health`, `/ready`, `/metrics` e `/docs` ficam internos |

```bash
make k8s-lint   # helm lint, kubeconform (esquema do Kubernetes 1.35), Trivy e Checkov
```

Exceções dos scanners ficam no próprio recurso, com o motivo (`checkov.io/skip*` e `deploy/.trivyignore.yaml`).
