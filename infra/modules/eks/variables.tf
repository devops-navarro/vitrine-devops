variable "nome" {
  description = "Nome do cluster."
  type        = string
}

variable "versao_kubernetes" {
  description = "Versão do Kubernetes do control plane."
  type        = string
  default     = "1.35"
}

variable "subnets_privadas" {
  description = "Subnets privadas para o control plane e os nós."
  type        = list(string)

  validation {
    condition     = length(var.subnets_privadas) >= 2
    error_message = "O EKS exige subnets em pelo menos duas AZs."
  }
}

variable "cidrs_acesso_publico_api" {
  description = "Faixas de IP que podem chamar a API do Kubernetes pela internet. Vazio: só de dentro da VPC."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cidrs_acesso_publico_api, "0.0.0.0/0")
    error_message = "API do cluster aberta para a internet inteira não: informe IPs específicos (ex.: 203.0.113.10/32)."
  }
}

variable "arns_administradores" {
  description = "Papéis ou usuários IAM com acesso de administrador ao cluster."
  type        = list(string)
  default     = []
}

variable "arquitetura" {
  description = "arm64 (Graviton, mais barato; exige imagens multi-arquitetura) ou x86_64."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.arquitetura)
    error_message = "Arquitetura precisa ser arm64 ou x86_64."
  }
}

variable "tipos_instancia" {
  description = "Tipos de instância dos nós. Vazio: o padrão da arquitetura."
  type        = list(string)
  default     = []
}

variable "capacidade" {
  description = "ON_DEMAND, ou SPOT (até 70% mais barato, mas a AWS pode retomar o nó com 2 minutos de aviso)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacidade)
    error_message = "Capacidade precisa ser ON_DEMAND ou SPOT."
  }
}

variable "nos" {
  description = "Quantidade de nós: mínimo, desejado e máximo."
  type = object({
    minimo   = number
    desejado = number
    maximo   = number
  })
  default = { minimo = 1, desejado = 2, maximo = 3 }

  validation {
    condition     = var.nos.minimo <= var.nos.desejado && var.nos.desejado <= var.nos.maximo
    error_message = "Precisa valer mínimo <= desejado <= máximo."
  }
}

variable "dias_retencao_logs" {
  description = "Por quantos dias guardar os logs do control plane."
  type        = number
  default     = 30
}

variable "pod_identities" {
  description = "Permissões AWS por service account, via EKS Pod Identity (sem chave e sem dar a permissão ao nó)."
  type = map(object({
    namespace       = string
    service_account = string
    politicas       = list(string)
  }))
  default = {}
}
