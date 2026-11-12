terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # Configuração parcial: bucket e região vêm do backend.hcl (fora do Git),
  # gerado a partir do bucket_state do ambiente bootstrap.
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
