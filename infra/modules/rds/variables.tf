variable "nome" {
  description = "Nome da instância e prefixo dos recursos (ex.: vitrine-dev)."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o banco fica."
  type        = string
}

variable "subnets_privadas" {
  description = "Subnets privadas, uma por AZ. O RDS exige pelo menos duas AZs no subnet group."
  type        = list(string)

  validation {
    condition     = length(var.subnets_privadas) >= 2
    error_message = "O subnet group do RDS precisa de subnets em pelo menos duas AZs."
  }
}

variable "security_groups_permitidos" {
  description = "Security groups que podem conectar na porta do PostgreSQL (os nós do EKS)."
  type        = list(string)

  validation {
    condition     = length(var.security_groups_permitidos) > 0
    error_message = "Informe ao menos um security group; o banco não aceita conexão de faixa de IP."
  }
}

variable "versao_postgres" {
  description = "Versão principal do PostgreSQL (a mesma do docker compose)."
  type        = string
  default     = "17"
}

variable "classe" {
  description = "Tipo de instância."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = startswith(var.classe, "db.")
    error_message = "A classe de instância do RDS começa com \"db.\"."
  }
}

variable "armazenamento_gb" {
  description = "Disco inicial, em GB."
  type        = number
  default     = 20
}

variable "armazenamento_maximo_gb" {
  description = "Até quanto o disco cresce sozinho, em GB."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Réplica em outra AZ, com troca automática se a principal cair. Dobra o custo; o laboratório desliga."
  type        = bool
  default     = true
}

variable "dias_backup" {
  description = "Dias de backup automático (restauração para qualquer ponto nesse intervalo)."
  type        = number
  default     = 7

  validation {
    condition     = var.dias_backup >= 1 && var.dias_backup <= 35
    error_message = "Backup automático entre 1 e 35 dias. Zero desligaria o backup."
  }
}

variable "protecao_exclusao" {
  description = "Impede apagar a instância por engano. Ambientes de laboratório desligam de propósito."
  type        = bool
  default     = true
}

variable "snapshot_final" {
  description = "Tira um snapshot antes de apagar a instância."
  type        = bool
  default     = true
}
