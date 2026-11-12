variable "nome" {
  description = "Nome do orçamento."
  type        = string
}

variable "limite_mensal_usd" {
  description = "Gasto mensal esperado, em dólares."
  type        = number

  validation {
    condition     = var.limite_mensal_usd > 0
    error_message = "O limite precisa ser maior que zero."
  }
}

variable "emails" {
  description = "Quem recebe os alertas."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.emails) > 0 && alltrue([for e in var.emails : can(regex("^[^@ ]+@[^@ ]+[.][^@ ]+$", e))])
    error_message = "Informe ao menos um e-mail válido."
  }
}

variable "filtro_tag_projeto" {
  description = "Conta só o gasto com a tag projeto igual a este valor. Vazio: a conta inteira."
  type        = string
  default     = ""
}
