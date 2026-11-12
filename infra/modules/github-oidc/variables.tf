variable "nome_papel" {
  description = "Nome do papel IAM que o pipeline assume."
  type        = string
}

variable "repositorio" {
  description = "Repositório do GitHub autorizado, no formato dono/nome."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.repositorio))
    error_message = "Use dono/nome, sem curinga: um \"*\" deixaria outros repositórios assumirem o papel."
  }
}

variable "branches" {
  description = "Branches cujas execuções podem assumir o papel."
  type        = list(string)
  default     = ["main"]

  validation {
    condition     = length(var.branches) > 0 && alltrue([for b in var.branches : !strcontains(b, "*")])
    error_message = "Informe branches exatas, sem curinga: um PR de qualquer branch não pode publicar imagem."
  }
}

variable "arns_repositorios_ecr" {
  description = "Repositórios do ECR em que o pipeline pode publicar."
  type        = list(string)

  validation {
    condition     = length(var.arns_repositorios_ecr) > 0 && alltrue([for a in var.arns_repositorios_ecr : startswith(a, "arn:") && !strcontains(a, "*")])
    error_message = "Informe os ARNs exatos dos repositórios, sem curinga."
  }
}

variable "criar_provider_oidc" {
  description = "Cria o provider OIDC do GitHub. Existe um por conta: se outro projeto já criou, use false."
  type        = bool
  default     = true
}
