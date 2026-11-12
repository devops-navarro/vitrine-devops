output "urls" {
  description = "URL de cada repositório, por serviço (para o docker push do CI)."
  value       = { for s, r in aws_ecr_repository.this : s => r.repository_url }
}

output "arns" {
  description = "ARN de cada repositório, para a política de IAM do CI."
  value       = [for r in aws_ecr_repository.this : r.arn]
}
