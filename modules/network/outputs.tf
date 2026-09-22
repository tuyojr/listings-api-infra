output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "ALB security group ID"
}

output "tasks_security_group_id" {
  value       = aws_security_group.tasks.id
  description = "ECS tasks security group ID"
}

output "rds_security_group_id" {
  value       = aws_security_group.rds.id
  description = "RDS security group ID"
}

output "flow_logs_bucket" {
  value       = aws_s3_bucket.flow_logs.id
  description = "S3 bucket receiving VPC flow logs"
}
