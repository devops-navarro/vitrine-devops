# Runbook · subir e destruir o ambiente na AWS

Passo a passo para criar o ambiente `dev` na conta real, conferir que funciona e destruir tudo no fim da sessão. Leva cerca de 30 minutos para subir e 15 para destruir. Custo estimado: **~US$ 0,22 por hora** com tudo ligado ([detalhe](../infra/README.md#custo-estimado)).

> Regra: o ambiente nasce e morre na mesma sessão. Antes de fechar o notebook, rode a seção "Destruir" até o fim.

## 1. Pré-requisitos (uma vez)

**Ferramentas no Mac:**

```bash
brew install awscli
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
terraform version   # 1.10 ou mais nova
aws --version
```

**Conta AWS:**

- [ ] Usuário root com MFA e sem chave de acesso.
- [ ] Acesso de administrador pelo **IAM Identity Center** (login pelo navegador, credencial temporária), não por usuário IAM com chave fixa.
- [ ] `aws configure sso` feito, com um perfil (os exemplos usam `vitrine`).

```bash
aws sso login --profile vitrine
export AWS_PROFILE=vitrine
aws sts get-caller-identity     # confere conta e papel antes de qualquer apply
```

Guarde o ARN do papel que aparece em `Arn` (troque `assumed-role/<papel>/<sessao>` pelo ARN do papel `arn:aws:iam::<conta>:role/aws-reserved/sso.amazonaws.com/<papel>`): ele vai em `arns_administradores`, para você ter acesso ao cluster.

## 2. Bucket do state (uma vez por conta)

Cria o bucket versionado e cifrado onde todos os outros ambientes guardam o state. Fica existindo entre as sessões (cerca de US$ 1 por mês).

```bash
cd infra/envs/bootstrap
terraform init
terraform plan -var owner=seu-nome      # conferir: 1 bucket, 1 chave KMS, nada mais
terraform apply -var owner=seu-nome
terraform output -raw bucket_state       # anote
```

O state deste ambiente fica no próprio Mac (`terraform.tfstate`, fora do Git). Guarde uma cópia num lugar seguro: sem ele, o Terraform não sabe que o bucket existe.

## 3. Configurar o ambiente dev

```bash
cd ../dev
cp backend.hcl.example backend.hcl            # colocar o bucket anotado no passo 2
cp terraform.tfvars.example terraform.tfvars  # preencher
curl -s https://checkip.amazonaws.com         # seu IP público, para cidrs_acesso_api (com /32)
```

Os dois arquivos ficam fora do Git. Confira com `git status` que nenhum deles aparece.

## 4. Subir

```bash
terraform init -backend-config=backend.hcl
terraform plan -out=plano.tfplan
```

**Leia o plano antes de aplicar.** Conferir:

- [ ] Só criações (`+`), nada de `destroy` numa conta que deveria estar vazia.
- [ ] 1 NAT Gateway, 2 nós `t4g.medium` Spot, 1 RDS `db.t4g.micro` sem Multi-AZ.
- [ ] `endpoint_public_access = true` só com o seu IP em `public_access_cidrs`.

```bash
terraform apply plano.tfplan     # ~15 a 20 minutos; o EKS é o mais demorado
```

Na primeira vez, a AWS manda um e-mail para confirmar a inscrição nos alertas do orçamento. **Confirme**, senão os alertas não chegam.

## 5. Conferir

```bash
aws eks update-kubeconfig --name "$(terraform output -raw cluster)"
kubectl get nodes -o wide          # 2 nós Ready, arquitetura arm64, IPs privados
kubectl get pods -A                # coredns, kube-proxy, aws-node, eks-pod-identity-agent Running
terraform output repositorios_ecr  # 3 repositórios
terraform output banco_endpoint
```

Segurança, de fora:

```bash
# API do cluster de outro IP (celular no 4G como hotspot, por exemplo): precisa falhar
# Banco: não tem endereço público
aws rds describe-db-instances --query 'DBInstances[].PubliclyAccessible'   # [false]
# Senha do banco não está no state
terraform show -json | grep -c '"password"'   # 0 ou só null
```

Idempotência na nuvem real:

```bash
terraform plan -detailed-exitcode   # código 0: nada a mudar
```

Anote as saídas e tire os prints para `docs/evidencias/`.

## 6. Destruir

```bash
terraform destroy      # confira a lista: tudo do ambiente dev, nada do bootstrap
```

Leva de 10 a 15 minutos. Depois, conferir que não sobrou nada cobrando:

```bash
aws eks list-clusters                                     # []
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'   # []
aws ec2 describe-addresses --query 'Addresses[].PublicIp' # [] (IP elástico parado também cobra)
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'   # []
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'   # []
```

Os repositórios do ECR com imagens não são apagados pelo destroy (`force_delete = false`). Se houver imagens, apague pelo console ou com `aws ecr batch-delete-image` e rode `terraform destroy` de novo.

As chaves KMS entram em período de exclusão de 7 dias; não é preciso fazer nada.

## Se algo der errado

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `Error acquiring the state lock` | Outro apply rodando, ou um que caiu no meio | Confirmar que ninguém está rodando; só então `terraform force-unlock <ID>` |
| `ExpiredToken` no meio do apply | Sessão do SSO expirou | `aws sso login --profile vitrine` e rodar o apply de novo (ele continua de onde parou) |
| `kubectl` sem resposta | Seu IP mudou | Atualizar `cidrs_acesso_api` e `terraform apply` |
| `kubectl`: `Unauthorized` | Papel não está em `arns_administradores` | Conferir o ARN do papel (não o da sessão) e aplicar de novo |
| Nós Spot não sobem | Falta de capacidade Spot na AZ | `capacidade_nos = "ON_DEMAND"` no `terraform.tfvars` e aplicar |
| Destroy travado na VPC | Algo criado fora do Terraform (um load balancer da Fase 4) ainda existe | Apagar primeiro os recursos do Kubernetes (`kubectl delete ingress --all -A`) e rodar o destroy de novo |
| Alerta de orçamento chegou | Algo ficou ligado | Seção 6 agora |
