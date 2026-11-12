# Roda sem conta AWS: o provider é simulado e o Terraform só faz o plano.
mock_provider "aws" {
  # Sem estes valores, o simulador inventa texto aleatório, e a chave KMS
  # recusaria a política por não ser JSON.
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
  nome_bucket = "vitrine-tfstate-teste"
}

run "bloqueia_todo_acesso_publico" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "O bucket do state precisa bloquear todo acesso público."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.state.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs precisam estar desligadas."
  }
}

run "versionado_e_cifrado_com_chave_propria" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_versioning.state.versioning_configuration).status == "Enabled"
    error_message = "Sem versionamento não dá para recuperar um state corrompido."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "O state precisa ser cifrado com KMS."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation
    error_message = "A chave do state precisa de rotação automática."
  }
}

run "recusa_acesso_sem_tls" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.somente_tls.statement :
      s.effect == "Deny" && anytrue([
        for c in s.condition : c.variable == "aws:SecureTransport" && contains(c.values, "false")
      ])
    ])
    error_message = "A política do bucket precisa negar acesso sem TLS."
  }
}

run "nao_apaga_o_bucket_com_state_dentro" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "force_destroy apagaria o state junto com o bucket."
  }
}

run "nome_invalido_e_recusado" {
  command = plan

  variables {
    nome_bucket = "Bucket_Com_Maiuscula"
  }

  expect_failures = [var.nome_bucket]
}

run "guardar_versoes_por_pouco_tempo_e_recusado" {
  command = plan

  variables {
    dias_versoes_antigas = 1
  }

  expect_failures = [var.dias_versoes_antigas]
}
