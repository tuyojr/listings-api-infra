output "execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution.arn
  description = "ARN of the shared ECS task execution role"
}

output "task_role_arns" {
  value       = { for k, v in aws_iam_role.task : k => v.arn }
  description = "Map of service name to its task role ARN"
}

output "db_bootstrap_task_role_arns" {
  value       = { for k, v in aws_iam_role.db_bootstrap_task : k => v.arn }
  description = "Map of service name to its db-bootstrap task role ARN"
}
