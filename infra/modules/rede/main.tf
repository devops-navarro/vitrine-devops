locals {
  # Públicas: /24 (256 IPs), só para load balancer e NAT.
  # Privadas: /20 (4.096 IPs), porque no EKS cada pod recebe um IP da VPC.
  # 10.0.0.0/24, 10.0.1.0/24...   e   10.0.16.0/20, 10.0.32.0/20...
  cidrs_publicas = [for i, _ in var.azs : cidrsubnet(var.cidr_vpc, 8, i)]
  cidrs_privadas = [for i, _ in var.azs : cidrsubnet(var.cidr_vpc, 4, i + 1)]

  quantidade_nat = var.nat_por_az ? length(var.azs) : 1
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.nome }
}

# O security group padrão aceita tráfego entre tudo que o usa. Sem regras,
# quem esquecer de escolher um security group fica isolado, não exposto.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.nome}-padrao-sem-regras" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.nome }
}

resource "aws_subnet" "publica" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.cidrs_publicas[count.index]
  # Nada ganha IP público só por estar aqui: load balancer e NAT recebem o seu.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.nome}-publica-${var.azs[count.index]}"
    # o load balancer controller do EKS cria ALBs públicos nas subnets com esta tag
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.nome_cluster_eks}" = "shared"
  }
}

resource "aws_subnet" "privada" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = local.cidrs_privadas[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name                                            = "${var.nome}-privada-${var.azs[count.index]}"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.nome_cluster_eks}" = "shared"
  }
}

resource "aws_eip" "nat" {
  count  = local.quantidade_nat
  domain = "vpc"

  tags = { Name = "${var.nome}-nat-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.quantidade_nat

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.publica[count.index].id

  tags = { Name = "${var.nome}-nat-${count.index}" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.nome}-publica" }
}

resource "aws_route_table_association" "publica" {
  count = length(var.azs)

  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# Uma tabela por AZ: com um NAT por AZ, cada uma sai pelo NAT da própria zona,
# e a queda de uma AZ não corta a saída das outras.
resource "aws_route_table" "privada" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.nat_por_az ? count.index : 0].id
  }

  tags = { Name = "${var.nome}-privada-${var.azs[count.index]}" }
}

resource "aws_route_table_association" "privada" {
  count = length(var.azs)

  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada[count.index].id
}

# --- flow logs: quem falou com quem, aceito ou recusado ---

resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_338:retenção de 1 ano custa mais que o ambiente; 30 dias cobrem a investigação de um incidente recente
  #checkov:skip=CKV_AWS_158:metadados de conexão (IPs e portas), já cifrados em repouso pelo CloudWatch; chave própria fica para a fase de melhorias
  name              = "/vpc/${var.nome}/flow-logs"
  retention_in_days = var.dias_retencao_flow_logs
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.nome}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs_escrita" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    # só o grupo de logs desta VPC
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "escrita-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_escrita.json
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}
