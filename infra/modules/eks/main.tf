locals {
  ami_type        = var.arquitetura == "arm64" ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
  tipos_instancia = length(var.tipos_instancia) > 0 ? var.tipos_instancia : (var.arquitetura == "arm64" ? ["t4g.medium"] : ["t3.medium"])
  acesso_publico  = length(var.cidrs_acesso_publico_api) > 0
}

data "aws_caller_identity" "atual" {}
data "aws_partition" "atual" {}

# --- chave dos secrets do Kubernetes ---------------------------------------

data "aws_iam_policy_document" "chave_secrets" {
  #checkov:skip=CKV_AWS_111:em política de chave KMS, Resource "*" é a própria chave; política padrão documentada pela AWS
  #checkov:skip=CKV_AWS_356:idem: o escopo é uma única chave
  #checkov:skip=CKV_AWS_109:idem: quem usa a chave é decidido pelo IAM da conta
  statement {
    sid       = "ContaAdministraAChave"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.atual.partition}:iam::${data.aws_caller_identity.atual.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "secrets" {
  description             = "Cifra os Secrets do Kubernetes no etcd (${var.nome})"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.chave_secrets.json
}

# --- control plane ---------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.nome}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.atual.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Criado antes do cluster para a retenção valer desde o primeiro log.
resource "aws_cloudwatch_log_group" "cluster" {
  #checkov:skip=CKV_AWS_338:1 ano de retenção custa mais que o ambiente; 30 dias cobrem a investigação de um incidente recente
  #checkov:skip=CKV_AWS_158:logs do control plane já cifrados em repouso pelo CloudWatch; chave própria fica para melhorias
  name              = "/aws/eks/${var.nome}/cluster"
  retention_in_days = var.dias_retencao_logs
}

resource "aws_eks_cluster" "this" {
  name     = var.nome
  version  = var.versao_kubernetes
  role_arn = aws_iam_role.cluster.arn

  # os cinco tipos: quem chamou a API (audit), autenticação, decisões do scheduler...
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.subnets_privadas
    endpoint_private_access = true
    # API pela internet só se houver IPs autorizados, e só deles
    endpoint_public_access = local.acesso_publico
    public_access_cidrs    = local.acesso_publico ? var.cidrs_acesso_publico_api : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  access_config {
    # Acesso só por access entries explícitas. Quem cria o cluster não vira
    # administrador escondido: o acesso aparece no código e no console.
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.arns_administradores)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.arns_administradores)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.atual.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# --- nós -------------------------------------------------------------------

data "aws_iam_policy_document" "nos_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nos" {
  name               = "${var.nome}-nos"
  assume_role_policy = data.aws_iam_policy_document.nos_assume.json
}

resource "aws_iam_role_policy_attachment" "nos" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    # só leitura: o nó baixa imagens, nunca publica
    "AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.nos.name
  policy_arn = "arn:${data.aws_partition.atual.partition}:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "nos" {
  name_prefix = "${var.nome}-nos-"

  # IMDSv2 obrigatório e hop limit 1: o pod, um salto a mais que o nó, não
  # alcança o serviço de metadados e não pega as credenciais do nó.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.nome}-no" }
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.nome}-padrao"
  node_role_arn   = aws_iam_role.nos.arn
  subnet_ids      = var.subnets_privadas

  ami_type       = local.ami_type
  instance_types = local.tipos_instancia
  capacity_type  = var.capacidade

  scaling_config {
    min_size     = var.nos.minimo
    desired_size = var.nos.desejado
    max_size     = var.nos.maximo
  }

  update_config {
    # atualização troca um nó por vez: o serviço continua de pé
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nos.id
    version = aws_launch_template.nos.latest_version
  }

  lifecycle {
    # o autoscaler muda a quantidade desejada; o Terraform não deve desfazer
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.nos]
}

# --- addons ----------------------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # coredns precisa de nós para ficar pronto
  depends_on = [aws_eks_node_group.this]
}

# --- Pod Identity: permissão AWS por service account -----------------------

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pod" {
  for_each = var.pod_identities

  name               = "${var.nome}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "pod" {
  for_each = merge([
    for nome, p in var.pod_identities : {
      for politica in p.politicas : "${nome}|${politica}" => { nome = nome, politica = politica }
    }
  ]...)

  role       = aws_iam_role.pod[each.value.nome].name
  policy_arn = each.value.politica
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = var.pod_identities

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.pod[each.key].arn
}
