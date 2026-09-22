output "address" {
  value       = aws_db_instance.main.address
  description = "RDS instance endpoint (hostname)"
}

output "port" {
  value       = aws_db_instance.main.port
  description = "RDS instance port"
}

output "database_name" {
  value       = aws_db_instance.main.db_name
  description = "Initial database name"
}

output "master_secret_arn" {
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
  description = "ARN of the AWS-managed master password secret"
}

output "instance_id" {
  value       = aws_db_instance.main.id
  description = "RDS instance identifier"
}
