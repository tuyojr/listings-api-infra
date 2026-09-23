data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "db_bootstrap" {
  for_each = var.tasks

  name              = "/ecs/${var.name_prefix}/db-bootstrap-${each.key}"
  retention_in_days = 7

  #checkov:skip=CKV_AWS_338:retention intentionally short (7 days) to control CloudWatch costs at this project's scale; not a compliance-bound workload.
  #checkov:skip=CKV_AWS_158:CloudWatch Logs are encrypted at rest by AWS-managed keys by default; a customer-managed key adds operational cost/complexity with no compliance driver here.
  tags = var.tags
}

resource "aws_ecs_task_definition" "db_bootstrap" {
  for_each = var.tasks

  family                   = "${var.name_prefix}-db-bootstrap-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = each.value.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "db-bootstrap-${each.key}"
      image     = each.value.image_uri
      essential = true
      command   = ["python3", "scripts/bootstrap_db_roles.py", each.key]

      environment = concat(
        [for k, v in each.value.environment_vars : { name = k, value = v }],
        [
          { name = "RDS_MASTER_SECRET_ARN", value = each.value.master_secret_arn },
          { name = "PYTHONPATH", value = "/app" },
        ]
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.db_bootstrap[each.key].name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      readonlyRootFilesystem = true
      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          drop = ["ALL"]
        }
        tmpfs = [{
          containerPath = "/tmp"
          size          = 64
        }]
      }
    }
  ])

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-bootstrap-${each.key}" })

  lifecycle {
    ignore_changes = [container_definitions]
  }
}
