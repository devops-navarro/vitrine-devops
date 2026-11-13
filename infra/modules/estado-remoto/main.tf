# Bucket do state do Terraform. O state guarda IDs, IPs e às vezes valores
# sensíveis de todos os recursos: é tratado como segredo.

data "aws_caller_identity" "atual" {}
data "aws_partition" "atual" {}

# Política explícita em vez da padrão implícita: a conta é dona da chave e o
# acesso de cada pessoa ou papel é decidido pelo IAM, num lugar só.
data "aws_iam_policy_document" "chave_state" {
  #checkov:skip=CKV_AWS_111:em política de chave KMS, Resource "*" é a própria chave; é a política padrão documentada pela AWS
  #checkov:skip=CKV_AWS_356:idem: o escopo já é uma única chave
  #checkov:skip=CKV_AWS_109:idem: quem pode usar a chave é decidido pelo IAM da conta
  statement {
    sid       = "ContaAdministraAChave"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.atual.partition}:iam::${data.aws_caller_identity.atual.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Cifra o state do Terraform (${var.nome_bucket})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.chave_state.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.nome_bucket}"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:log de acesso exigiria outro bucket só para isso; o CloudTrail já registra quem leu o state
  #checkov:skip=CKV_AWS_144:replicação para outra região dobra o custo de um bucket que se recria em minutos
  #checkov:skip=CKV2_AWS_62:ninguém consome eventos deste bucket
  bucket = var.nome_bucket

  # apagar o state por engano é pior do que precisar esvaziar o bucket à mão
  force_destroy = false
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    # ACL desligada: quem manda é só a política do bucket e o IAM
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    # cada apply gera uma versão nova: dá para voltar a um state anterior
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.dias_versoes_antigas
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Recusa qualquer acesso sem TLS, mesmo de quem tem permissão.
data "aws_iam_policy_document" "somente_tls" {
  statement {
    sid     = "SomenteTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  count = var.exigir_tls ? 1 : 0

  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.somente_tls.json

  # a política pública só pode entrar depois do bloqueio de acesso público
  depends_on = [aws_s3_bucket_public_access_block.state]
}
