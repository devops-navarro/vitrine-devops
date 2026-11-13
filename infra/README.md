# infra

Infraestrutura da Vitrine na AWS, em Terraform. Tudo aqui é validado e testado **sem conta AWS**; o `apply` na conta real segue o runbook (Fase 3).

```
infra/
  modules/        módulos reutilizáveis, sem state próprio, cada um com tests/
  envs/
    bootstrap/    bucket do state remoto (state local: é o único)
    dev/          ambiente de estudo: rede, ECR, EKS, RDS, OIDC do CI e orçamento
    local/        os mesmos módulos aplicados num emulador da AWS (Moto)
```

## Convenções

- **Versões fixas:** Terraform `>= 1.10`, provider AWS `~> 6.73`. Os ambientes versionam o `.terraform.lock.hcl` com hashes para macOS (arm64) e Linux (amd64).
- **Tags em tudo**, pelo `default_tags` do provider: `projeto`, `ambiente`, `owner`, `ttl`, `gerenciado_por`.
- **State remoto** no S3 com lock nativo (`use_lockfile = true`, Terraform 1.10+), sem tabela DynamoDB.
- **Exceção do Checkov só com motivo escrito** no próprio recurso (`#checkov:skip=REGRA:motivo`).

## Checks

```bash
make tf-check      # tudo abaixo
make tf-fmt        # formatação
make tf-validate   # sintaxe e tipos, em cada módulo e ambiente
make tf-lint       # tflint com o plugin AWS
make tf-sec        # Checkov
make tf-test       # terraform test com provider simulado
```

Os testes usam `mock_provider "aws"`: o Terraform faz o plano de verdade, mas o provider é simulado, então não há credencial nem chamada à AWS. Cada teste confere uma propriedade de segurança ou uma validação de entrada.

## Módulos

### estado-remoto

Bucket do state: versionado (para recuperar um state corrompido), cifrado com chave KMS própria com rotação, sem ACL, sem acesso público, negando qualquer acesso sem TLS, com `force_destroy = false`. Versões antigas expiram em 90 dias.

### rede

VPC em 2 ou 3 AZs, com uma subnet pública e uma privada em cada.

| Item | Escolha |
| --- | --- |
| CIDRs | Calculados com `cidrsubnet`: públicas `/24` (load balancer e NAT), privadas `/20` (no EKS cada pod recebe um IP da VPC) |
| Saída das privadas | NAT Gateway. Um só por padrão (cerca de US$ 32 por mês cada); `nat_por_az = true` dá um por AZ, para a queda de uma zona não cortar a saída das outras |
| IP público | Nenhuma subnet atribui automaticamente |
| EKS | Tags `kubernetes.io/role/elb` (públicas) e `internal-elb` (privadas), para o load balancer controller achar as subnets |
| Security group padrão | Sem regras: quem esquecer de escolher um fica isolado, não exposto |
| Flow logs | Todo o tráfego, no CloudWatch, 30 dias |

```
10.0.0.0/16
├── 10.0.0.0/24    pública  AZ a
├── 10.0.1.0/24    pública  AZ b
├── 10.0.16.0/20   privada  AZ a
└── 10.0.32.0/20   privada  AZ b
```

### ecr

Um repositório por serviço (`vitrine/clientes`, `vitrine/catalogo`, `vitrine/pedidos`):

- **Tags imutáveis**: a imagem `v1.2.3` não é trocada por baixo; para mudar, publica-se outra tag.
- **Scan na publicação** e **cifra KMS** (chave gerenciada pela AWS, sem custo de chave própria).
- **Ciclo de vida**: imagens sem tag somem em 7 dias; das com tag, ficam as 20 mais recentes (no mínimo 5, para ter para onde voltar num rollback).
- `force_delete = false`: um `destroy` não apaga repositório com imagens.

### rds

PostgreSQL 17 gerenciado, nas subnets privadas.

- **Senha do administrador gerada pela AWS** e guardada no Secrets Manager (`manage_master_user_password`): não passa pelo código, pelo plan nem pelo state.
- **TLS obrigatório** (`rds.force_ssl = 1`), disco cifrado, sem endereço público.
- **Entrada só por security group** (os nós do EKS), porta 5432; nunca por faixa de IPs.
- Consultas acima de 1 s vão para o log, exportado para o CloudWatch.
- **Padrões seguros para produção**: Multi-AZ, proteção contra exclusão, snapshot final e 7 dias de backup. O ambiente de laboratório desliga Multi-AZ, proteção e snapshot de forma explícita, porque é criado e destruído a cada sessão.

Os usuários de cada serviço (ADR 0001) não são criados aqui: o mesmo `infra/postgres/bootstrap.sql` roda contra o RDS como um Job no cluster (Fase 4), com a senha do administrador lida do Secrets Manager.

### eks

Cluster Kubernetes gerenciado, com nós nas subnets privadas.

| Item | Escolha |
| --- | --- |
| API do Kubernetes | Privada por padrão. Pública só para IPs informados; `0.0.0.0/0` é recusado |
| Acesso ao cluster | Só por access entries (`authentication_mode = "API"`); quem cria o cluster não vira administrador escondido |
| Secrets | Cifrados no etcd com chave KMS própria, com rotação |
| Logs do control plane | Os cinco tipos (inclusive `audit`), 30 dias |
| Nós | Node group gerenciado, IMDSv2 obrigatório com hop limit 1 (pod não alcança as credenciais do nó), disco cifrado, só leitura no ECR, troca de um nó por vez |
| Arquitetura | `arm64` (Graviton, ~20% mais barato) por padrão; exige imagens multi-arquitetura. `x86_64` disponível |
| Capacidade | `ON_DEMAND` ou `SPOT` |
| Addons | `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent` |
| Permissão para pods | EKS Pod Identity: um papel IAM por service account, sem chave e sem dar a permissão ao nó |

### github-oidc

O GitHub Actions publica imagens no ECR **sem chave de acesso guardada**. O GitHub emite um token OIDC por execução; a AWS troca por credenciais temporárias (1 hora no máximo) se o token for:

- emitido para a AWS (`aud = sts.amazonaws.com`);
- deste repositório e de uma das branches informadas (`sub = repo:devops-navarro/vitrine-devops:ref:refs/heads/main`), por comparação exata.

O papel só faz login no registro e publica nos repositórios informados: sem curinga, sem apagar imagem. Curinga no repositório, na branch ou nos ARNs é recusado na validação. O provider OIDC é um por conta; se já existir, `criar_provider_oidc = false` reaproveita.


### orcamento

AWS Budget mensal com alerta por e-mail em 50% e 80% do gasto real e quando a **previsão** do mês passa de 100%. É a rede de segurança de quem estuda com a própria conta: avisa se um ambiente ficar ligado por esquecimento.

## Ambiente dev

`infra/envs/dev` junta os módulos:

```
rede (2 AZs, 1 NAT) ──> eks (nós Spot, arm64) ──> rds (aceita só o security group do cluster)
ecr (3 repositórios) ──> github-oidc (pipeline publica só neles)
orcamento (conta inteira)
```

- **Backend S3** com configuração parcial: `backend.hcl` (fora do Git) traz o bucket criado pelo `bootstrap`. Há um `backend.hcl.example`.
- **Variáveis** em `terraform.tfvars` (fora do Git), a partir do `terraform.tfvars.example`: dono, e-mail dos alertas, seu IP para o `kubectl` e o papel de administrador.
- **AZs explícitas** (`us-east-1a` e `us-east-1b`): "as primeiras que a AWS listar" muda quando ela cria uma zona nova, e o Terraform tentaria mover as subnets.
- **Escolhas de laboratório, escritas no ambiente**: um NAT só, nós Spot, RDS sem Multi-AZ, sem proteção contra exclusão, sem snapshot final e com 1 dia de backup. Os módulos nascem com o contrário.

### Custo estimado

Preços de referência de `us-east-1`, por hora, com o ambiente ligado. São estimativas: confira na [calculadora da AWS](https://calculator.aws/) antes do apply.

| Item | US$/hora |
| --- | --- |
| Control plane do EKS | 0,100 |
| NAT Gateway (sem contar o tráfego) e seu IP público | 0,050 |
| 2 nós `t4g.medium` Spot (On-Demand: ~0,067) | ~0,025 |
| RDS `db.t4g.micro`, uma AZ, 20 GB | ~0,019 |
| Discos dos nós (2 × 30 GB gp3) | ~0,007 |
| Logs do control plane, chaves KMS, segredo | ~0,020 |
| **Total** | **~0,22** |

Uma sessão de 4 horas fica em torno de **US$ 1**. Esquecido ligado, passa de **US$ 150 por mês**: é para isso que existe o orçamento com alerta de previsão. O load balancer da Fase 4 soma cerca de US$ 0,023 por hora.

Fica cobrando mesmo com o ambiente destruído: o bucket do state e a chave KMS dele (`bootstrap`), cerca de US$ 1 por mês. As chaves KMS do ambiente entram em período de exclusão de 7 dias ao serem apagadas.

## Apply de verdade sem conta AWS

`infra/envs/local` aplica os módulos no [Moto](https://github.com/getmoto/moto), um emulador da AWS de código aberto, em duas etapas como na conta real: o `bootstrap` cria o bucket do state, e a `plataforma` guarda o state **nele**, com lock nativo, aplicando rede, ECR e o OIDC do pipeline (EKS e RDS ficam de fora: o suporte do emulador é raso demais para provar algo).

```bash
make tf-local-up        # emulador em https://localhost:4566
make tf-local-apply     # bootstrap + plataforma (29 recursos)
make tf-local-plan      # falha se o plan seguinte tiver mudança
make tf-local-destroy   # destroi a plataforma; o bucket do state fica (force_destroy = false)
make tf-local-down      # desliga o emulador, que zera tudo
```

O CI roda esse ciclo em todo PR.

Cuidados e limitações:
- **Nada vai para a AWS**: credenciais falsas, todos os serviços apontados para o emulador e `AWS_ENDPOINT_URL` como rede de segurança para qualquer serviço esquecido. (Foi esquecendo o S3 Control que uma chamada chegou à AWS de verdade e voltou com 403.)
- **HTTPS** com o certificado gerado pelo emulador (`insecure = true` só nestes ambientes).
- **TLS no bucket desligado só aqui** (`exigir_tls = false`): o Moto não preenche `aws:SecureTransport` e nega até acesso por HTTPS. Na AWS a regra fica ligada, que é o padrão do módulo.
- **Tags de bucket**: o provider grava pelo S3 Control e o Moto não guarda, então o plan do `bootstrap` local sempre mostra as tags de novo. O da `plataforma`, que é o verificado, fica limpo.
- Por que Moto e não LocalStack: as versões atuais do LocalStack exigem token de conta, mesmo no plano gratuito.

## Aplicar na AWS

O passo a passo para subir, conferir e destruir o ambiente na conta real está em [docs/runbook-aws.md](../docs/runbook-aws.md). As decisões da infraestrutura estão na [ADR 0003](../docs/adr/0003-infraestrutura-aws.md).
