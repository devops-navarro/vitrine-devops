mock_provider "aws" {}

variables {
  servicos = ["clientes", "catalogo", "pedidos"]
}

run "um_repositorio_por_servico" {
  command = plan

  assert {
    condition     = toset([for r in aws_ecr_repository.this : r.name]) == toset(["vitrine/clientes", "vitrine/catalogo", "vitrine/pedidos"])
    error_message = "Cada serviço precisa do seu repositório, com o prefixo."
  }
}

run "tags_imutaveis_scan_e_cifra" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Tag publicada não pode ser sobrescrita."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : one(r.image_scanning_configuration).scan_on_push])
    error_message = "Toda imagem precisa ser varrida ao ser publicada."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : one(r.encryption_configuration).encryption_type == "KMS"])
    error_message = "Os repositórios precisam de cifra KMS."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : !r.force_delete])
    error_message = "Um destroy não pode apagar repositório com imagens."
  }
}

run "ciclo_de_vida_limpa_sem_tag_e_limita_quantidade" {
  command = plan

  variables {
    imagens_mantidas = 10
  }

  assert {
    condition = alltrue([
      for p in aws_ecr_lifecycle_policy.this :
      jsondecode(p.policy).rules[0].selection.tagStatus == "untagged" &&
      jsondecode(p.policy).rules[0].selection.countNumber == 7 &&
      jsondecode(p.policy).rules[1].selection.countNumber == 10
    ])
    error_message = "A política precisa apagar imagens sem tag em 7 dias e manter as N mais recentes."
  }
}

run "nome_de_servico_invalido_e_recusado" {
  command = plan

  variables {
    servicos = ["Clientes"]
  }

  expect_failures = [var.servicos]
}

run "guardar_poucas_imagens_e_recusado" {
  command = plan

  variables {
    imagens_mantidas = 2
  }

  expect_failures = [var.imagens_mantidas]
}
