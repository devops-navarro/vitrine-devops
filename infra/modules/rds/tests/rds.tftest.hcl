mock_provider "aws" {}

variables {
  nome                       = "vitrine-teste"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnets_privadas           = ["subnet-aaa", "subnet-bbb"]
  security_groups_permitidos = ["sg-nos-eks"]
}

run "banco_fechado_para_a_internet" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "O banco não pode ter endereço público."
  }

  assert {
    condition     = toset(aws_db_subnet_group.this.subnet_ids) == toset(var.subnets_privadas)
    error_message = "O banco só pode ficar nas subnets privadas."
  }
}

run "senha_gerenciada_pela_aws_e_fora_do_state" {
  command = plan

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "A senha do administrador precisa ser gerada e guardada pelo Secrets Manager."
  }

  assert {
    condition     = aws_db_instance.this.password == null
    error_message = "Nenhuma senha pode ser passada pelo Terraform (ela iria para o state)."
  }
}

run "cifra_e_tls_obrigatorios" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_encrypted
    error_message = "O disco do banco precisa ser cifrado."
  }

  assert {
    condition     = anytrue([for p in aws_db_parameter_group.this.parameter : p.name == "rds.force_ssl" && p.value == "1"])
    error_message = "O banco precisa recusar conexão sem TLS."
  }
}

run "so_os_security_groups_permitidos_entram" {
  command = plan

  variables {
    security_groups_permitidos = ["sg-nos-eks", "sg-bastion"]
  }

  assert {
    condition     = toset([for r in aws_vpc_security_group_ingress_rule.postgres : r.referenced_security_group_id]) == toset(["sg-nos-eks", "sg-bastion"])
    error_message = "A entrada precisa ser exatamente dos security groups informados."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.postgres : r.cidr_ipv4 == null && r.from_port == 5432 && r.to_port == 5432])
    error_message = "Só a porta 5432, e nunca a partir de uma faixa de IPs."
  }
}

run "protegido_por_padrao" {
  command = plan

  assert {
    condition     = aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot
    error_message = "Por padrão o banco precisa de proteção contra exclusão e snapshot final."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 7
    error_message = "Backup automático de ao menos 7 dias por padrão."
  }

  assert {
    condition     = aws_db_instance.this.multi_az
    error_message = "Por padrão o banco precisa de réplica em outra AZ."
  }
}

run "laboratorio_desliga_as_protecoes_de_proposito" {
  command = plan

  variables {
    protecao_exclusao = false
    snapshot_final    = false
    multi_az          = false
  }

  assert {
    condition     = !aws_db_instance.this.deletion_protection && aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.final_snapshot_identifier == null
    error_message = "Desligadas as proteções, o destroy precisa funcionar sem snapshot."
  }
}

run "uma_subnet_so_e_recusada" {
  command = plan

  variables {
    subnets_privadas = ["subnet-aaa"]
  }

  expect_failures = [var.subnets_privadas]
}

run "sem_security_group_permitido_e_recusado" {
  command = plan

  variables {
    security_groups_permitidos = []
  }

  expect_failures = [var.security_groups_permitidos]
}

run "backup_desligado_e_recusado" {
  command = plan

  variables {
    dias_backup = 0
  }

  expect_failures = [var.dias_backup]
}
