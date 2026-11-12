resource "aws_db_subnet_group" "this" {
  name       = var.nome
  subnet_ids = var.subnets_privadas
}

resource "aws_security_group" "this" {
  name        = "${var.nome}-rds"
  description = "PostgreSQL: so os security groups permitidos entram"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.nome}-rds" }
}

# Entrada só de security groups (os nós do EKS), nunca de uma faixa de IPs:
# um IP novo na VPC não ganha acesso ao banco só por estar lá.
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.security_groups_permitidos)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL a partir de ${each.value}"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.nome}-postgres${var.versao_postgres}"
  family = "postgres${var.versao_postgres}"

  # recusa conexão sem TLS: senha e dados nunca trafegam abertos na rede
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # registra consultas acima de 1 s: é por elas que se começa a investigar lentidão
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_118:monitoramento aprimorado exige mais um papel IAM; as métricas básicas do CloudWatch bastam até a Fase 6
  #checkov:skip=CKV_AWS_353:Performance Insights fica para a fase de melhorias, junto com a análise de custo
  identifier     = var.nome
  engine         = "postgres"
  engine_version = var.versao_postgres
  instance_class = var.classe

  db_name  = "vitrine"
  username = "vitrine_admin"
  # A AWS gera a senha e guarda no Secrets Manager, com rotação. Ela não passa
  # pelo código, pelo plan nem pelo state do Terraform.
  manage_master_user_password = true

  allocated_storage     = var.armazenamento_gb
  max_allocated_storage = var.armazenamento_maximo_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period    = var.dias_backup
  copy_tags_to_snapshot      = true
  deletion_protection        = var.protecao_exclusao
  skip_final_snapshot        = !var.snapshot_final
  final_snapshot_identifier  = var.snapshot_final ? "${var.nome}-final" : null
  auto_minor_version_upgrade = true

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
}
