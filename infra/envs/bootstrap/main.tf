provider "aws" {
  region = var.regiao

  # Toda tag aplicada pelo provider: nenhum recurso escapa sem elas.
  default_tags {
    tags = {
      projeto        = "vitrine"
      ambiente       = "bootstrap"
      owner          = var.owner
      ttl            = var.ttl
      gerenciado_por = "terraform"
    }
  }
}

data "aws_caller_identity" "atual" {}

module "estado_remoto" {
  source = "../../modules/estado-remoto"

  # conta e região no nome: único no mundo sem depender de sorte
  nome_bucket = "vitrine-tfstate-${data.aws_caller_identity.atual.account_id}-${var.regiao}"
}
