output "endpoint" {
  description = "Endereço do banco (POSTGRES_HOST dos serviços)."
  value       = aws_db_instance.this.address
}

output "porta" {
  description = "Porta do PostgreSQL."
  value       = aws_db_instance.this.port
}

output "nome_banco" {
  description = "Banco criado na instância (POSTGRES_DB dos serviços)."
  value       = aws_db_instance.this.db_name
}

output "arn_segredo_admin" {
  description = "Segredo no Secrets Manager com o usuário e a senha do administrador."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group do banco."
  value       = aws_security_group.this.id
}
