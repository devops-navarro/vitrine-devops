terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # O bucket do state remoto é criado aqui, então este ambiente não pode
  # guardar o próprio state nele: fica local. É o único.
  backend "local" {}
}
