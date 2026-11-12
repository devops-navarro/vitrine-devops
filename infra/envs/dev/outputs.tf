output "cluster" {
  description = "Nome do cluster, para: aws eks update-kubeconfig --name <cluster>."
  value       = module.eks.nome
}

output "repositorios_ecr" {
  description = "URL de cada repositório de imagem."
  value       = module.ecr.urls
}

output "papel_pipeline" {
  description = "ARN do papel que o GitHub Actions assume (segredo AWS_ROLE_ARN do repositório)."
  value       = module.github_oidc.arn_papel
}

output "banco_endpoint" {
  description = "Endereço do PostgreSQL (POSTGRES_HOST dos serviços)."
  value       = module.rds.endpoint
}

output "banco_segredo_admin" {
  description = "Segredo do Secrets Manager com o usuário e a senha do administrador do banco."
  value       = module.rds.arn_segredo_admin
}
