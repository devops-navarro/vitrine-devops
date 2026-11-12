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
