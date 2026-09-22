output "cluster_id" {
  value       = aws_ecs_cluster.main.id
  description = "ECS cluster ID"
}

output "cluster_name" {
  value       = aws_ecs_cluster.main.name
  description = "ECS cluster name"
}

output "cluster_arn" {
  value       = aws_ecs_cluster.main.arn
  description = "ECS cluster ARN"
}
