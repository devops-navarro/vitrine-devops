output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "cidr_vpc" {
  description = "Faixa de IPs da VPC."
  value       = aws_vpc.this.cidr_block
}

output "subnets_publicas" {
  description = "IDs das subnets públicas (load balancers e NAT)."
  value       = aws_subnet.publica[*].id
}

output "subnets_privadas" {
  description = "IDs das subnets privadas (nós do EKS e banco)."
  value       = aws_subnet.privada[*].id
}
