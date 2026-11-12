output "nome" {
  description = "Nome do cluster."
  value       = aws_eks_cluster.this.name
}

output "endpoint" {
  description = "Endereço da API do Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "certificado_ca" {
  description = "Certificado da autoridade do cluster, em base64 (para o kubeconfig)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "security_group_cluster" {
  description = "Security group que o EKS cria para o cluster e os nós (para liberar o RDS)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "arns_papeis_pods" {
  description = "Papel IAM de cada Pod Identity."
  value       = { for k, r in aws_iam_role.pod : k => r.arn }
}
