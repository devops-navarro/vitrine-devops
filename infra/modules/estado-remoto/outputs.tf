output "nome_bucket" {
  description = "Nome do bucket, para o bloco backend dos outros ambientes."
  value       = aws_s3_bucket.state.id
}

output "arn_bucket" {
  description = "ARN do bucket, para políticas de IAM."
  value       = aws_s3_bucket.state.arn
}

output "arn_chave_kms" {
  description = "ARN da chave KMS que cifra o state."
  value       = aws_kms_key.state.arn
}
