variable "prefixo" {
  description = "Prefixo dos repositórios (ex.: vitrine fica vitrine/clientes)."
  type        = string
  default     = "vitrine"
}

variable "servicos" {
  description = "Um repositório por serviço."
  type        = set(string)

  validation {
    condition     = alltrue([for s in var.servicos : can(regex("^[a-z][a-z0-9-]*$", s))])
    error_message = "Nome de serviço: minúsculas, números e hífen, começando por letra."
  }
}

variable "imagens_mantidas" {
  description = "Quantas imagens com tag guardar por repositório. As mais antigas são apagadas."
  type        = number
  default     = 20

  validation {
    condition     = var.imagens_mantidas >= 5
    error_message = "Guarde ao menos 5 imagens: é o que permite voltar versões num rollback."
  }
}
