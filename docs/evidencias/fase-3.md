# Fase 3 · AWS com Terraform

Versão `v0.3.0`. A infraestrutura da Vitrine na AWS em módulos Terraform, validada, testada e aplicada sem conta AWS. O apply na conta real segue o [runbook](../runbook-aws.md).

## O que foi entregue

| Entrega | PR |
| --- | --- |
| Base: estrutura `modules/` e `envs/`, versões fixas, tags padrão, módulo do state remoto, CI com fmt, validate, tflint, Checkov e `terraform test` | #60 |
| Módulo `rede`: VPC em 2 AZs, subnets calculadas, NAT único ou por AZ, flow logs | #61 |
| Módulo `ecr`: tag imutável, scan, cifra, ciclo de vida | #62 |
| Módulo `rds`: PostgreSQL 17 privado, senha no Secrets Manager, TLS obrigatório, padrões de produção | #63 |
| Módulo `eks`: API privada, access entries, secrets cifrados, nós com IMDSv2 e hop limit 1, Pod Identity | #64 |
| Módulo `github-oidc`: CI na AWS sem chave guardada, `sub` exato | #70 |
| Módulo `orcamento` e ambiente `dev` compondo tudo | #71 |
| Apply, plan e destroy num emulador da AWS (Moto), também no CI | #72 |
| [Runbook](../runbook-aws.md) e [ADR 0003](../adr/0003-infraestrutura-aws.md) | #73 |

## Números

| Medida | Resultado |
| --- | --- |
| Módulos | 7, cada um com testes |
| `terraform test` com provider simulado | 53 testes |
| Checkov | 213 checagens aprovadas, 0 reprovadas; cada exceção com motivo escrito no recurso |
| tflint (plugin AWS) | sem problemas |
| Emulador, em todo PR | bootstrap 8 recursos, plataforma 29 recursos, plan seguinte sem mudanças, destroy de 29 |
| Credenciais AWS no CI | nenhuma |
| Custo estimado do ambiente dev | ~US$ 0,22 por hora |

## Comportamentos provados

| Cenário | Resultado | PR |
| --- | --- | --- |
| Bloqueio de acesso público do bucket desligado | Teste falha: "O bucket do state precisa bloquear todo acesso público." | #60 |
| Rota privada apontada para o Internet Gateway | Teste falha: "Subnet privada precisa sair pelo NAT" | #61 |
| Tag de imagem mutável | Teste falha: "Tag publicada não pode ser sobrescrita." | #62 |
| Banco com endereço público | Teste falha: "O banco não pode ter endereço público." | #63 |
| Hop limit 2 nos nós | Teste falha: "pods não podem pegar as credenciais do nó" | #64 |
| Curinga no `sub` do OIDC | Teste falha: "Só execuções deste repositório na main podem assumir o papel" | #70 |
| Dois plans simultâneos no state remoto | O segundo: `Error acquiring the state lock` | #72 |
| Destroy do bucket do state com conteúdo | `BucketNotEmpty`: `force_destroy = false` protegendo o state | #72 |
| Acesso ao bucket do state sem TLS (emulador) | Negado pela política do próprio módulo | #72 |

## Achados no caminho

- O provider simulado inventa texto para JSON e ARNs; os testes passaram a simular valores coerentes (#60, #61).
- Tupla × lista nas comparações do `terraform test` (#61, #64).
- Checkov: chave KMS sem política explícita, Multi-AZ desligado por padrão, AZs escolhidas por "as primeiras da lista" (#60, #63, #71).
- tflint: variável declarada e não usada (#64).
- Disco do Mac cheio por 7 cópias de 729 MB do provider; resolvido com cache compartilhado de plugins (#71).
- Um endpoint esquecido (S3 Control) mandou uma chamada para a AWS de verdade; resolvido apontando todos os serviços e com `AWS_ENDPOINT_URL` (#72).
- O emulador não preenche `aws:SecureTransport`; variável `exigir_tls`, ligada por padrão e testada (#72).
- LocalStack passou a exigir token de conta; troca pelo Moto (#72).

## O que ainda depende da conta real

O emulador não cobre EKS e RDS de forma útil. Subir o cluster, os nós, os addons e o banco de verdade, e conferir acesso, segurança e custo, é a primeira execução do [runbook](../runbook-aws.md), registrada aqui quando acontecer.

## Como reproduzir

```bash
make tf-check                                     # fmt, validate, tflint, Checkov, testes
make tf-local-up && make tf-local-apply           # apply no emulador
make tf-local-plan                                # sem mudanças
make tf-local-destroy && make tf-local-down
```
