# Etapa 2 no emulador: state remoto no bucket da etapa 1, com lock nativo, e os
# módulos que o emulador suporta bem (rede, ECR e o OIDC do pipeline).

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  backend "s3" {
    # 123456789012 é a conta fixa do emulador
    bucket       = "vitrine-tfstate-123456789012-us-east-1"
    key          = "local/plataforma.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true

    access_key                  = "teste"
    secret_key                  = "teste"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
    insecure                    = true

    endpoints = {
      s3  = "https://localhost:4566"
      sts = "https://localhost:4566"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  access_key                  = "teste"
  secret_key                  = "teste"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  # certificado gerado pelo emulador, que não é de autoridade conhecida
  insecure = true

  endpoints {
    ec2  = "https://localhost:4566"
    ecr  = "https://localhost:4566"
    iam  = "https://localhost:4566"
    logs = "https://localhost:4566"
    sts  = "https://localhost:4566"
  }

  default_tags {
    tags = {
      projeto        = "vitrine"
      ambiente       = "local"
      owner          = "laboratorio"
      ttl            = "fim-da-sessao"
      gerenciado_por = "terraform"
    }
  }
}

module "rede" {
  source = "../../../modules/rede"

  nome             = "vitrine-local"
  azs              = ["us-east-1a", "us-east-1b"]
  nome_cluster_eks = "vitrine-local"
}

module "ecr" {
  source = "../../../modules/ecr"

  servicos = ["clientes", "catalogo", "pedidos"]
}

module "github_oidc" {
  source = "../../../modules/github-oidc"

  nome_papel            = "vitrine-local-pipeline"
  repositorio           = "devops-navarro/vitrine-devops"
  arns_repositorios_ecr = module.ecr.arns
}

output "vpc_id" {
  description = "VPC criada no emulador."
  value       = module.rede.vpc_id
}

output "subnets_privadas" {
  description = "Subnets privadas criadas no emulador."
  value       = module.rede.subnets_privadas
}

output "repositorios_ecr" {
  description = "Repositórios criados no emulador."
  value       = module.ecr.urls
}
