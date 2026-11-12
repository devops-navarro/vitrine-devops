variable "nome" {
  description = "Prefixo dos nomes dos recursos (ex.: vitrine-dev)."
  type        = string
}

variable "cidr_vpc" {
  description = "Faixa de IPs da VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_vpc, 0)) && tonumber(split("/", var.cidr_vpc)[1]) <= 16
    error_message = "Use um CIDR válido de /16 ou maior: as subnets privadas são /20 e o EKS consome um IP por pod."
  }
}

variable "azs" {
  description = "Zonas de disponibilidade. Uma subnet pública e uma privada em cada."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Use 2 ou 3 AZs: com uma só, a queda de um data center derruba tudo."
  }
}

variable "nat_por_az" {
  description = "Um NAT Gateway por AZ (alta disponibilidade) ou um só para todas (mais barato)."
  type        = bool
  default     = false
}

variable "nome_cluster_eks" {
  description = "Cluster EKS que vai usar as subnets (para as tags de descoberta dos load balancers)."
  type        = string
}

variable "dias_retencao_flow_logs" {
  description = "Por quantos dias guardar os flow logs da VPC."
  type        = number
  default     = 30
}
