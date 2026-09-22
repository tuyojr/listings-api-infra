output "arns" {
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
  description = "Map of secret name to ARN"
}

output "names" {
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.name }
  description = "Map of secret name to Secrets Manager name"
}

output "kms_key_arn" {
  value       = aws_kms_key.secrets.arn
  description = "KMS key ARN used for secrets encryption"
}
