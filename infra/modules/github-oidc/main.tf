locals {
  url_github = "https://token.actions.githubusercontent.com"
  # "sub" do token do GitHub: identifica repositório e branch da execução
  subs_permitidos = [for b in var.branches : "repo:${var.repositorio}:ref:refs/heads/${b}"]
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.criar_provider_oidc ? 1 : 0

  url            = local.url_github
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.criar_provider_oidc ? 0 : 1
  url   = local.url_github
}

locals {
  arn_provider = var.criar_provider_oidc ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Quem pode assumir: só tokens deste repositório e destas branches, emitidos
# para a AWS. Sem a condição de "sub", qualquer repositório do GitHub entraria.
data "aws_iam_policy_document" "confianca" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.arn_provider]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subs_permitidos
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name                 = var.nome_papel
  assume_role_policy   = data.aws_iam_policy_document.confianca.json
  max_session_duration = 3600
}

# O que pode fazer: publicar imagens nos repositórios informados, e só isso.
data "aws_iam_policy_document" "publicar_imagens" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken não aceita escopo por recurso; é só o login no registro e não dá acesso a repositório nenhum
  #checkov:skip=CKV_AWS_111:idem: a escrita está no outro bloco, limitada aos ARNs dos repositórios
  statement {
    sid       = "LoginNoRegistro"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PublicarNosRepositoriosDaVitrine"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = var.arns_repositorios_ecr
  }
}

resource "aws_iam_role_policy" "publicar_imagens" {
  name   = "publicar-imagens"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.publicar_imagens.json
}
