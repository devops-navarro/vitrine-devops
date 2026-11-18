# deploy

Tudo o que roda os serviços em Kubernetes. Localmente, num cluster [kind](https://kind.sigs.k8s.io/) com a mesma versão do EKS. As decisões estão na [ADR 0004](../docs/adr/0004-kubernetes-entrega-e-gitops.md).

```
deploy/
  kind/cluster.yaml     o cluster local: 1 control plane e 2 workers, Kubernetes 1.35.8 fixado por digest
  plataforma/           o que o cluster precisa antes dos serviços: ingress e métricas
  charts/servico/       chart Helm único, que implanta qualquer um dos três serviços
  servicos/             os valores de cada serviço: só o que muda entre eles
  banco/                namespace, PostgreSQL e bootstrap dos usuários (só no cluster local)
  gitops/               Argo CD: AppProject, Application do banco e ApplicationSet dos serviços
  ambientes/local/      a versão implantada de cada serviço: deploy e rollback são commits aqui
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

## Subindo a aplicação

```bash
make k8s-up      # cluster
make k8s-app     # banco + os três serviços (imagens com a tag do commit)
```

Depois, pelo ingress em `http://127.0.0.1:8080`:

```bash
make k8s-smoke   # o mesmo smoke test do compose
make k8s-seed    # o mesmo seed; ARGS=--sem-mudancas confere que não muda nada
```

O ingress publica só `/clientes`, `/produtos` e `/pedidos`. `/health`, `/ready`, `/metrics` e `/docs` respondem 404 de fora, inclusive com tentativas como `/clientes/../metrics`. Por isso, pelo ingress, o smoke considera um serviço pronto quando a rota de negócio responde 401 sem chave (`SMOKE_VIA_INGRESS=1`).

`make k8s-app` é a soma de:
- `k8s-banco`: namespace, segredos, PostgreSQL e bootstrap;
- `k8s-servicos`: constrói as imagens com a tag do commit (mais `-sujo` se houver mudança não commitada), carrega no kind e faz `helm upgrade --install` de cada serviço.

## Banco, segredos e bootstrap

| Peça | Como funciona |
| --- | --- |
| Namespace `vitrine` | Pod Security Standard **`restricted`** em modo enforce: a API do Kubernetes recusa pod que rode como root ou peça privilégio. Vale também para o banco |
| PostgreSQL | StatefulSet com volume persistente de 1 GB, versão fixa (`17.11-alpine3.24`), uid 70, sistema de arquivos só leitura. NetworkPolicy: só pods da Vitrine entram na 5432; o banco não abre conexão com ninguém |
| Segredos | `vitrine-banco` (senhas do administrador e de cada serviço) e `vitrine-api` (chaves da API) criados **na hora** a partir do `.env`, com `kubectl create secret --dry-run \| kubectl apply`. Não existem em arquivo nem no Git |
| Bootstrap | Job que roda o mesmo `infra/postgres/bootstrap.sql` do Mac e do compose, montado de um ConfigMap: um usuário por serviço, dono só do próprio schema (ADR 0001). A NetworkPolicy dele só permite DNS e banco |

### Na AWS

O cluster local substitui três peças da AWS, e o resto é igual:

| Local | AWS |
| --- | --- |
| StatefulSet `postgres` | RDS (`infra/modules/rds`); `POSTGRES_HOST` passa a ser o endpoint do RDS |
| Secrets criados a partir do `.env` | External Secrets lendo o Secrets Manager, com permissão por Pod Identity (`infra/modules/eks`). A senha do administrador é a que o próprio RDS guarda |
| Job de bootstrap contra o PostgreSQL do cluster | O mesmo Job, apontado para o RDS |

Os charts dos serviços não mudam: os nomes dos Secrets e das chaves são os mesmos.


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

## GitOps com Argo CD

No modo GitOps, ninguém aplica nada no cluster: o Argo CD lê este repositório e deixa o cluster igual ao Git.

```bash
make k8s-up
make k8s-gitops            # instala o Argo CD e cria as Applications; segredos a partir do .env
make k8s-argocd-status     # SYNC e SAUDE de cada Application
make k8s-smoke
```

Para testar uma branch antes do merge: `make k8s-gitops REVISAO=<branch>`.

```
GitHub (main) ──lido a cada 60 s──> Argo CD ──aplica──> namespace vitrine
   deploy/banco                       Application banco
   deploy/charts/servico      ┐
   deploy/servicos/<s>.yaml   ├──     ApplicationSet servicos ──> clientes, catalogo, pedidos
   deploy/ambientes/local/<s>.yaml ┘
```

| Peça | Papel |
| --- | --- |
| AppProject `vitrine` | Só aceita este repositório como origem e o namespace `vitrine` como destino |
| Application `banco` | Namespace, PostgreSQL e o bootstrap (hook `PostSync`, recriado a cada sincronização) |
| ApplicationSet `servicos` | Uma Application por serviço, do mesmo chart, com dois arquivos de valores: o do serviço e o do ambiente |
| `deploy/ambientes/local/<s>.yaml` | A tag implantada (o commit que gerou a imagem no GHCR) e o que mais variar por ambiente |
| `prune` e `selfHeal` | O que sai do Git sai do cluster; mudança feita na mão é desfeita |

**Implantar** uma versão: commit trocando `imagem.tag` em `deploy/ambientes/local/<servico>.yaml` para o commit de uma imagem publicada pelo workflow `imagens`.

**Voltar** uma versão: `git revert` desse commit.

Segredos e o SQL do bootstrap não vêm do Git: `make k8s-gitops` cria a partir do `.env`. Na AWS, quem cria é o External Secrets.

Dois ajustes que o Argo CD exigiu no Traefik local (`deploy/plataforma/traefik.yaml`):
- **Endereço no status do Ingress** (`ingressEndpoint.ip: 127.0.0.1`): sem ele, o Argo CD considera o Ingress em progresso para sempre. No EKS, o AWS Load Balancer Controller preenche com o endereço do ALB.
- **Troca de pod tirando o antigo primeiro**: com `hostPort`, só um pod por nó ocupa a porta 80, e a estratégia padrão (subir o novo antes) trava.
