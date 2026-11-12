output "arn_papel" {
  description = "Papel que o workflow assume (role-to-assume do aws-actions/configure-aws-credentials)."
  value       = aws_iam_role.pipeline.arn
}
