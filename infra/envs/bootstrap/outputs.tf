output "bucket_state" {
  description = "Bucket para o bloco backend \"s3\" dos outros ambientes."
  value       = module.estado_remoto.nome_bucket
}
