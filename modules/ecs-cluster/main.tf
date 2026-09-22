resource "aws_cloudwatch_log_group" "exec" {
  name              = "/aws/ecs/${var.name_prefix}/exec"
  retention_in_days = var.environment == "prod" ? 30 : 7

  #checkov:skip=CKV_AWS_338:retention intentionally short (7/30 days) to control CloudWatch costs at this project's scale; not a compliance-bound workload.
  #checkov:skip=CKV_AWS_158:CloudWatch Logs are encrypted at rest by AWS-managed keys by default; a customer-managed key adds operational cost/complexity with no compliance driver here.
  tags = var.tags
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
      }
    }
  }

  #checkov:skip=CKV_AWS_224:ECS exec session logging is enabled (see execute_command_configuration above); CMK encryption for it carries the same cost/complexity tradeoff noted on aws_cloudwatch_log_group.exec.
  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.environment == "prod" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 1
    base              = var.environment == "prod" ? 1 : 0
  }
}
