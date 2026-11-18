# deploy

Tudo o que roda os serviços em Kubernetes. Localmente, num cluster [kind](https://kind.sigs.k8s.io/) com a mesma versão do EKS.

```
deploy/
  kind/cluster.yaml     o cluster local: 1 control plane e 2 workers, Kubernetes 1.35.8 fixado por digest
  plataforma/           o que o cluster precisa antes dos serviços: ingress e métricas
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
