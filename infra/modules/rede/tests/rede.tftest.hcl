# Roda sem conta AWS: provider simulado. Os runs com "apply" fazem o
# simulador gerar IDs, para dar para conferir por onde cada rota sai.
mock_provider "aws" {
  # ARNs com formato válido: o flow log valida o formato dos ARNs que recebe.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/vpc/vitrine-teste/flow-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/vitrine-teste-flow-logs"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  nome             = "vitrine-teste"
  azs              = ["us-east-1a", "us-east-1b"]
  nome_cluster_eks = "vitrine-teste"
}

run "subnets_calculadas_sem_sobreposicao" {
  command = plan

  assert {
    condition     = aws_subnet.publica[*].cidr_block == ["10.0.0.0/24", "10.0.1.0/24"]
    error_message = "Subnets públicas deveriam ser 10.0.0.0/24 e 10.0.1.0/24."
  }

  assert {
    condition     = aws_subnet.privada[*].cidr_block == ["10.0.16.0/20", "10.0.32.0/20"]
    error_message = "Subnets privadas deveriam ser /20 a partir de 10.0.16.0, sem encostar nas públicas."
  }

  assert {
    condition     = tolist(aws_subnet.publica[*].availability_zone) == var.azs && tolist(aws_subnet.privada[*].availability_zone) == var.azs
    error_message = "Cada AZ precisa de uma subnet pública e uma privada."
  }
}

run "nenhuma_subnet_da_ip_publico_automatico" {
  command = plan

  assert {
    condition     = !anytrue(concat(aws_subnet.publica[*].map_public_ip_on_launch, aws_subnet.privada[*].map_public_ip_on_launch))
    error_message = "Nenhuma subnet pode atribuir IP público automaticamente."
  }
}

run "privadas_saem_pelo_nat_e_publicas_pelo_internet_gateway" {
  command = apply

  assert {
    condition = alltrue([
      for rt in aws_route_table.privada :
      # atributo não preenchido pode vir como null ou como texto vazio
      !contains([null, ""], one(rt.route).nat_gateway_id) && contains([null, ""], one(rt.route).gateway_id)
    ])
    error_message = "Subnet privada precisa sair pelo NAT, nunca direto pelo Internet Gateway."
  }

  assert {
    condition     = one(aws_route_table.publica.route).gateway_id == aws_internet_gateway.this.id
    error_message = "Subnet pública precisa sair pelo Internet Gateway."
  }
}

run "um_nat_so_por_padrao" {
  command = apply

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "O padrão é um NAT só, para economizar."
  }

  assert {
    condition     = length(distinct([for rt in aws_route_table.privada : one(rt.route).nat_gateway_id])) == 1
    error_message = "Com um NAT só, todas as subnets privadas saem por ele."
  }
}

run "um_nat_por_az_quando_pedido" {
  command = apply

  variables {
    nat_por_az = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Com nat_por_az, cada AZ precisa do seu NAT."
  }

  assert {
    condition     = length(distinct([for rt in aws_route_table.privada : one(rt.route).nat_gateway_id])) == 2
    error_message = "Cada subnet privada precisa sair pelo NAT da própria AZ."
  }

  assert {
    condition     = aws_nat_gateway.this[*].subnet_id == aws_subnet.publica[*].id
    error_message = "Cada NAT precisa ficar na subnet pública da sua AZ."
  }
}

run "subnets_marcadas_para_os_load_balancers_do_eks" {
  command = plan

  assert {
    condition = alltrue([
      for s in aws_subnet.publica : s.tags["kubernetes.io/role/elb"] == "1" && s.tags["kubernetes.io/cluster/vitrine-teste"] == "shared"
    ])
    error_message = "Subnets públicas precisam das tags para o ALB público do EKS."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.privada : s.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Subnets privadas precisam da tag de load balancer interno."
  }
}

run "security_group_padrao_sem_regras" {
  command = plan

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "O security group padrão não pode liberar nada."
  }
}

run "flow_logs_de_todo_o_trafego" {
  command = plan

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Flow logs precisam registrar tráfego aceito e recusado."
  }
}

run "tres_azs" {
  command = plan

  variables {
    azs = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition     = length(aws_subnet.privada) == 3 && aws_subnet.privada[2].cidr_block == "10.0.48.0/20"
    error_message = "Com 3 AZs, a terceira privada deveria ser 10.0.48.0/20."
  }
}

run "uma_az_so_e_recusada" {
  command = plan

  variables {
    azs = ["us-east-1a"]
  }

  expect_failures = [var.azs]
}

run "vpc_pequena_demais_e_recusada" {
  command = plan

  variables {
    cidr_vpc = "10.0.0.0/24"
  }

  expect_failures = [var.cidr_vpc]
}
