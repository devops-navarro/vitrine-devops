# Etapa 1 no emulador: o mesmo módulo do bootstrap real cria o bucket do state.
# State local, como no bootstrap da conta de verdade.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # Credenciais falsas: o emulador aceita qualquer uma, e nada sai da máquina.
  access_key                  = "teste"
  secret_key                  = "teste"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  # certificado gerado pelo emulador, que não é de autoridade conhecida
  insecure          = true
  s3_use_path_style = true

  # Todo serviço usado precisa estar aqui: um que faltar vai para a AWS de
  # verdade (o provider lê tags de bucket pelo S3 Control, por exemplo).
  endpoints {
    s3        = "https://localhost:4566"
    s3control = "https://localhost:4566"
    kms       = "https://localhost:4566"
    iam       = "https://localhost:4566"
    sts       = "https://localhost:4566"
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

data "aws_caller_identity" "atual" {}

module "estado_remoto" {
  source = "../../../modules/estado-remoto"

  nome_bucket = "vitrine-tfstate-${data.aws_caller_identity.atual.account_id}-us-east-1"

  # O Moto não preenche aws:SecureTransport e nega até acesso por HTTPS.
  # Na AWS a regra fica ligada (padrão do módulo).
  exigir_tls = false
}

output "bucket_state" {
  description = "Bucket onde a etapa 2 guarda o state."
  value       = module.estado_remoto.nome_bucket
}
