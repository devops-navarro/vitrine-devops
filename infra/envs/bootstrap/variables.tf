variable "regiao" {
  description = "Região da AWS."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Responsável pelos recursos (vai na tag owner)."
  type        = string
}

variable "ttl" {
  description = "Até quando o recurso deve existir (vai na tag ttl)."
  type        = string
  default     = "permanente"
}
