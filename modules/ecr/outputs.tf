output "repository_urls" {
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
  description = "Map of repo name to URL"
}

output "repository_arns" {
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
  description = "Map of repo name to ARN"
}

output "kms_key_arn" {
  value       = aws_kms_key.ecr.arn
  description = "KMS key ARN used for repository encryption - the ECS task execution role needs kms:Decrypt on this to pull images"
}
