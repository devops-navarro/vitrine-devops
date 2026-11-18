# ADR 0004 · Kubernetes, entrega de imagens e GitOps

- **Status:** aceita

## Contexto

Os três serviços precisam rodar em Kubernetes: no EKS quando houver sessão na AWS ([ADR 0003](0003-infraestrutura-aws.md)) e, no dia a dia, num cluster local. O caminho até o cluster precisa ser repetível, seguro e auditável: quem mudou o quê, com qual imagem, e como voltar.

As perguntas eram:

1. Que cluster usar fora da AWS, sem que ele se comporte diferente do EKS?
2. Como empacotar três serviços muito parecidos sem triplicar manifesto?
3. Que garantias de segurança impor, e onde?
4. Como as imagens chegam ao cluster, e o que garante que são confiáveis?
5. Quem aplica as mudanças no cluster?

## Decisão

**Cluster local com kind, na mesma versão do EKS.** Kubernetes 1.35.8 com a imagem fixada por digest, 1 control plane e 2 workers (para espalhamento de réplicas e PodDisruptionBudget terem efeito). O mesmo cluster sobe no CI a cada PR (`k8s-deploy`). Traefik como ingress controller local; o recurso continua sendo o `Ingress` padrão, que no EKS vira ALB ([ADR 0002](0002-exposicao-com-alb-e-waf.md)).

**Um chart Helm para os três serviços** (`deploy/charts/servico`), com um arquivo de valores por serviço só com o que muda.

**Segurança imposta pela plataforma, não pela boa vontade:**
- namespace com Pod Security Standard `restricted` em modo enforce;
- contêineres sem root, só leitura, sem capabilities, seccomp padrão, sem token da API;
- NetworkPolicy negando tudo que não está listado, nos dois sentidos;
- Trivy e Checkov nos manifestos renderizados, no CI.

**Disponibilidade:** rolling update com `maxUnavailable: 0`, `preStop`, réplicas espalhadas por nó, PodDisruptionBudget e HPA por CPU. Request de CPU e memória, limite só de memória.

**Migrations como Job de hook** (`pre-install`, `pre-upgrade` no Helm; viram `PreSync` no Argo CD): se falham, a versão antiga continua no ar.

**Imagens:** construídas pelo pipeline, nunca no notebook, para `linux/amd64` e `linux/arm64` (os nós do EKS são Graviton). Trivy barra vulnerabilidade alta ou crítica com correção. Só a `main` publica, com a tag do commit (nunca `latest`), proveniência e SBOM. Registro: GHCR no laboratório; ECR na AWS (`infra/modules/ecr`, tags imutáveis).

**GitOps com Argo CD:** o cluster segue a `main`. Um AppProject restringe origem (este repositório) e destino (namespace `vitrine`); um ApplicationSet gera uma Application por serviço; `prune` e `selfHeal` ligados. A versão implantada de cada serviço fica em `deploy/ambientes/<ambiente>/<servico>.yaml`: implantar e voltar versão são commits.

**Segredos fora do Git:** no cluster local, criados a partir do `.env`; na AWS, External Secrets lendo o Secrets Manager com Pod Identity.

## Alternativas consideradas

- **minikube ou k3d no lugar do kind.** Funcionariam; o kind é o que o próprio projeto Kubernetes usa nos testes, sobe igual no Mac e no CI e aceita fixar a imagem do nó por digest.
- **ingress-nginx.** Foi o padrão por anos, mas o projeto Kubernetes o aposentou; não faz sentido começar um projeto com ele.
- **Gateway API no lugar de Ingress.** É o futuro do roteamento no Kubernetes; o `Ingress` ainda é o que o AWS Load Balancer Controller suporta de forma mais madura e o que a maioria das vagas pede. Migrar é uma melhoria anotada.
- **Kustomize em vez de Helm.** Bom para variações pequenas; com hooks de migration, valores por serviço e validações (`required`, recusa de `latest`), o Helm resolve com menos peças.
- **Três charts, um por serviço.** Mais liberdade por serviço, mas três cópias divergindo com o tempo.
- **Limite de CPU.** Evitaria um vizinho barulhento, mas causa throttling com o nó ocioso. Ficam request de CPU e limite de memória.
- **`kubectl apply` ou `helm upgrade` a partir do pipeline (push).** Mais simples, mas o pipeline precisaria de credencial de administrador do cluster, e uma mudança feita à mão no cluster ficaria lá sem ninguém perceber. Com o Argo CD (pull), o cluster busca o Git e desfaz a deriva.
- **Flux no lugar do Argo CD.** Equivalente em capacidade; o Argo CD tem interface visual e aparece mais nas vagas.
- **Promoção automática de versão** (o pipeline abrir o PR que troca a tag do ambiente). Um PR aberto com o `GITHUB_TOKEN` não dispara os workflows, então os checks obrigatórios nunca rodariam; exigiria um GitHub App ou o Argo CD Image Updater. Por ora, a promoção é um commit feito por uma pessoa, e a automação está nas melhorias.

## Consequências

- O que roda no cluster é rastreável até o commit: tag da imagem = commit, versão implantada = commit no Git, proveniência anexada à imagem.
- Voltar versão é `git revert`; desfazer mudança feita à mão é automático (`selfHeal`).
- Pod que viole o `restricted` é recusado pela API: a regra vale também para quem não leu o chart.
- No cluster local, o Traefik usa `hostPort`; a troca de pod dele tem alguns segundos sem ingress. No EKS isso não existe.
- O Argo CD precisa que o Ingress publique um endereço no status para considerá-lo saudável (localmente, `127.0.0.1`; no EKS, o ALB).
- Segredos são a única peça que o Git não descreve; isso é deliberado e documentado.
