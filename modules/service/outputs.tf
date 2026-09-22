output "service_name" {
  value       = aws_ecs_service.main.name
  description = "ECS service name"
}

output "service_arn" {
  value       = aws_ecs_service.main.id
  description = "ECS service ARN"
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.main.arn
  description = "Task definition ARN"
}

output "target_group_arn" {
  value       = aws_lb_target_group.main.arn
  description = "Target group ARN for ALB routing"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.main.name
  description = "CloudWatch log group name"
}
