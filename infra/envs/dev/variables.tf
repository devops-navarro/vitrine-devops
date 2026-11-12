variable "regiao" {
  description = "Região da AWS."
  type        = string
  default     = "us-east-1"
}

variable "azs" {
  description = "Zonas de disponibilidade, explícitas: \"as primeiras que a AWS listar\" muda quando ela cria uma zona nova."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = alltrue([for az in var.azs : startswith(az, var.regiao)])
    error_message = "As AZs precisam ser da região escolhida."
  }
}

variable "owner" {
  description = "Responsável pelos recursos (tag owner)."
  type        = string
}

variable "ttl" {
  description = "Até quando o ambiente deve existir (tag ttl). O ambiente de estudo é destruído ao fim de cada sessão."
  type        = string
  default     = "fim-da-sessao"
}

variable "cidrs_acesso_api" {
  description = "IPs que podem usar o kubectl pela internet (ex.: o IP público de casa, /32)."
  type        = list(string)
  default     = []
}

variable "arns_administradores" {
  description = "Papéis ou usuários IAM com acesso de administrador ao cluster."
  type        = list(string)
  default     = []
}

variable "capacidade_nos" {
  description = "ON_DEMAND ou SPOT para os nós do EKS."
  type        = string
  default     = "SPOT"
}

variable "repositorio_github" {
  description = "Repositório que pode publicar imagens no ECR."
  type        = string
  default     = "devops-navarro/vitrine-devops"
}

variable "criar_provider_oidc" {
  description = "Cria o provider OIDC do GitHub na conta (false se já existir)."
  type        = bool
  default     = true
}

variable "limite_orcamento_usd" {
  description = "Gasto mensal esperado na conta, em dólares."
  type        = number
  default     = 30
}

variable "emails_alertas" {
  description = "Quem recebe os alertas de orçamento."
  type        = list(string)
  sensitive   = true
}
