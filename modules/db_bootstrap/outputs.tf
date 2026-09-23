output "task_definition_families" {
  value       = { for k, v in aws_ecs_task_definition.db_bootstrap : k => v.family }
  description = "Map of service name to its db-bootstrap task definition family name, for `aws ecs run-task --task-definition`"
}
