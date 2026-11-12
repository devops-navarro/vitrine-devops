resource "aws_ecr_repository" "this" {
  for_each = var.servicos

  name = "${var.prefixo}/${each.key}"

  # Tag publicada não muda: a imagem v1.2.3 de hoje é a mesma amanhã, e o que
  # está em produção não é trocado por baixo sem um deploy.
  image_tag_mutability = "IMMUTABLE"

  # apagar um repositório com imagens é decisão manual, não efeito de um destroy
  force_delete = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    # chave gerenciada pela AWS: cifra com KMS sem o custo de uma chave própria
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Imagens sem tag (camadas de builds substituídos) somem em 7 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Mantém as ${var.imagens_mantidas} imagens com tag mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.imagens_mantidas
        }
        action = { type = "expire" }
      },
    ]
  })
}
