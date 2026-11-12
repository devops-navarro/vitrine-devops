variable "nome_bucket" {
  description = "Nome do bucket do state. Precisa ser único no mundo inteiro."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.nome_bucket))
    error_message = "Nome de bucket S3 inválido: só minúsculas, números e hífen, de 3 a 63 caracteres."
  }
}

variable "dias_versoes_antigas" {
  description = "Por quantos dias guardar versões antigas do state, para recuperar um state corrompido."
  type        = number
  default     = 90

  validation {
    condition     = var.dias_versoes_antigas >= 7
    error_message = "Guarde ao menos 7 dias de versões antigas."
  }
}

variable "exigir_tls" {
  description = "Política do bucket negando acesso sem TLS. Só o emulador local desliga, porque não informa aws:SecureTransport."
  type        = bool
  default     = true
}
