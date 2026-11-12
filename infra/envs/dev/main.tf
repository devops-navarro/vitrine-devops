provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      projeto        = "vitrine"
      ambiente       = "dev"
      owner          = var.owner
      ttl            = var.ttl
      gerenciado_por = "terraform"
    }
  }
}

locals {
  nome = "vitrine-dev"
}

module "rede" {
  source = "../../modules/rede"

  nome             = local.nome
  azs              = var.azs
  nome_cluster_eks = local.nome
  # um NAT só: ambiente de estudo, destruído ao fim da sessão
  nat_por_az = false
}

module "ecr" {
  source = "../../modules/ecr"

  servicos = ["clientes", "catalogo", "pedidos"]
}

module "eks" {
  source = "../../modules/eks"

  nome                     = local.nome
  subnets_privadas         = module.rede.subnets_privadas
  cidrs_acesso_publico_api = var.cidrs_acesso_api
  arns_administradores     = var.arns_administradores
  capacidade               = var.capacidade_nos
  nos                      = { minimo = 1, desejado = 2, maximo = 3 }
}

module "rds" {
  #checkov:skip=CKV_AWS_293:ambiente de estudo destruído ao fim de cada sessão; o módulo liga a proteção por padrão
  #checkov:skip=CKV_AWS_157:idem: réplica em outra AZ dobraria o custo de um banco que vive algumas horas
  source = "../../modules/rds"

  nome                       = local.nome
  vpc_id                     = module.rede.vpc_id
  subnets_privadas           = module.rede.subnets_privadas
  security_groups_permitidos = [module.eks.security_group_cluster]

  # Ambiente de estudo, criado e destruído a cada sessão: sem réplica, sem
  # proteção contra exclusão e sem snapshot final. Escrito aqui de propósito.
  multi_az          = false
  protecao_exclusao = false
  snapshot_final    = false
  dias_backup       = 1
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  nome_papel            = "${local.nome}-pipeline"
  repositorio           = var.repositorio_github
  arns_repositorios_ecr = module.ecr.arns
  criar_provider_oidc   = var.criar_provider_oidc
}

module "orcamento" {
  source = "../../modules/orcamento"

  nome              = "vitrine"
  limite_mensal_usd = var.limite_orcamento_usd
  emails            = var.emails_alertas
}
