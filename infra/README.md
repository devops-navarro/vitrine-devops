# infra

Infraestrutura da Vitrine na AWS, em Terraform. Tudo aqui é validado e testado **sem conta AWS**; o `apply` na conta real segue o runbook (Fase 3).

```
infra/
  modules/        módulos reutilizáveis, sem state próprio, cada um com tests/
  envs/
    bootstrap/    bucket do state remoto (state local: é o único)
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
