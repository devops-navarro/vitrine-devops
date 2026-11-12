mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  nome             = "vitrine-teste"
  subnets_privadas = ["subnet-aaa", "subnet-bbb"]
}

run "api_sem_acesso_publico_por_padrao" {
  command = plan

  assert {
    condition     = one(aws_eks_cluster.this.vpc_config).endpoint_public_access == false
    error_message = "Sem IPs autorizados, a API do cluster não pode ser pública."
  }

  assert {
    condition     = one(aws_eks_cluster.this.vpc_config).endpoint_private_access
    error_message = "A API precisa ser alcançável de dentro da VPC."
  }
}

run "api_publica_so_dos_ips_autorizados" {
  command = plan

  variables {
    cidrs_acesso_publico_api = ["203.0.113.10/32"]
  }

  assert {
    condition     = one(aws_eks_cluster.this.vpc_config).endpoint_public_access && toset(one(aws_eks_cluster.this.vpc_config).public_access_cidrs) == toset(["203.0.113.10/32"])
    error_message = "A API pública só pode aceitar os IPs informados."
  }
}

run "api_aberta_para_a_internet_e_recusada" {
  command = plan

  variables {
    cidrs_acesso_publico_api = ["0.0.0.0/0"]
  }

  expect_failures = [var.cidrs_acesso_publico_api]
}

run "secrets_cifrados_e_todos_os_logs" {
  command = plan

  assert {
    condition     = one(aws_eks_cluster.this.encryption_config).resources == toset(["secrets"])
    error_message = "Os Secrets do Kubernetes precisam ser cifrados com KMS."
  }

  assert {
    condition     = aws_kms_key.secrets.enable_key_rotation
    error_message = "A chave dos secrets precisa de rotação."
  }

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "Os cinco tipos de log do control plane precisam estar ligados (o audit principalmente)."
  }
}

run "acesso_so_por_access_entry_explicita" {
  command = plan

  variables {
    arns_administradores = ["arn:aws:iam::123456789012:role/admin"]
  }

  assert {
    condition     = one(aws_eks_cluster.this.access_config).authentication_mode == "API"
    error_message = "O acesso ao cluster precisa ser por access entries."
  }

  assert {
    condition     = one(aws_eks_cluster.this.access_config).bootstrap_cluster_creator_admin_permissions == false
    error_message = "Quem cria o cluster não pode virar administrador sem aparecer no código."
  }

  assert {
    condition     = length(aws_eks_access_policy_association.admin) == 1
    error_message = "Cada administrador informado precisa da sua access entry."
  }
}

run "nos_privados_com_imdsv2_e_disco_cifrado" {
  command = plan

  assert {
    condition     = toset(aws_eks_node_group.this.subnet_ids) == toset(var.subnets_privadas)
    error_message = "Os nós só podem ficar nas subnets privadas."
  }

  assert {
    condition     = one(aws_launch_template.nos.metadata_options).http_tokens == "required" && one(aws_launch_template.nos.metadata_options).http_put_response_hop_limit == 1
    error_message = "IMDSv2 obrigatório com hop limit 1: pods não podem pegar as credenciais do nó."
  }

  assert {
    condition     = one(one(aws_launch_template.nos.block_device_mappings).ebs).encrypted == "true"
    error_message = "O disco dos nós precisa ser cifrado."
  }
}

run "no_so_le_imagens" {
  command = plan

  assert {
    condition     = contains(keys(aws_iam_role_policy_attachment.nos), "AmazonEC2ContainerRegistryReadOnly") && !anytrue([for k in keys(aws_iam_role_policy_attachment.nos) : strcontains(k, "PowerUser") || strcontains(k, "FullAccess")])
    error_message = "O nó só pode ler do ECR."
  }
}

run "arm_por_padrao" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this.ami_type == "AL2023_ARM_64_STANDARD" && tolist(aws_eks_node_group.this.instance_types) == tolist(["t4g.medium"])
    error_message = "O padrão é Graviton (arm64)."
  }
}

run "x86_quando_pedido" {
  command = plan

  variables {
    arquitetura = "x86_64"
  }

  assert {
    condition     = aws_eks_node_group.this.ami_type == "AL2023_x86_64_STANDARD" && tolist(aws_eks_node_group.this.instance_types) == tolist(["t3.medium"])
    error_message = "Com x86_64, AMI e instância precisam ser x86."
  }
}

run "pod_identity_por_service_account" {
  command = plan

  variables {
    pod_identities = {
      lb-controller = {
        namespace       = "kube-system"
        service_account = "aws-load-balancer-controller"
        politicas       = ["arn:aws:iam::123456789012:policy/lb-controller"]
      }
    }
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["lb-controller"].service_account == "aws-load-balancer-controller" && aws_eks_pod_identity_association.this["lb-controller"].namespace == "kube-system"
    error_message = "A permissão precisa ir para a service account informada, não para o nó."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.pod) == 1
    error_message = "Cada política informada precisa ser anexada ao papel do pod."
  }
}

run "addons_incluem_o_agente_de_pod_identity" {
  command = plan

  assert {
    condition     = contains(keys(aws_eks_addon.this), "eks-pod-identity-agent")
    error_message = "Sem o agente, o Pod Identity não funciona."
  }
}

run "quantidade_de_nos_incoerente_e_recusada" {
  command = plan

  variables {
    nos = { minimo = 3, desejado = 1, maximo = 2 }
  }

  expect_failures = [var.nos]
}
