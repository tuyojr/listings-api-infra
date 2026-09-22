data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${var.name_prefix}/${var.service_name}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  #checkov:skip=CKV_AWS_338:retention intentionally short (7/30 days) to control CloudWatch costs at this project's scale; not a compliance-bound workload.
  #checkov:skip=CKV_AWS_158:CloudWatch Logs are encrypted at rest by AWS-managed keys by default; a customer-managed key adds operational cost/complexity with no compliance driver here.
  tags = var.tags
}

resource "aws_lb_target_group" "main" {
  name        = "${var.name_prefix}-${var.service_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  #checkov:skip=CKV_AWS_378:standard TLS-termination-at-the-ALB pattern; ALB-to-target traffic stays inside private subnets restricted by security group, TLS terminates at the internet-facing HTTPS listener.
  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.service_name}-tg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.image_uri
      essential = true

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      environment = [
        for k, v in var.environment_vars : { name = k, value = v }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}/health')\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # The image already runs as a non-root user set in its Dockerfile
      # (USER appuser, a dynamically assigned system UID) - no `user`
      # override here, since forcing a fixed UID could mismatch the file
      # ownership baked into the image.
      readonlyRootFilesystem = true

      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          drop = ["ALL"]
        }
        # readonlyRootFilesystem leaves no writable directory for Python's
        # tempfile module; give it a small tmpfs.
        tmpfs = [{
          containerPath = "/tmp"
          size          = 64
        }]
      }
    }
  ])

  tags = merge(var.tags, { Name = var.service_name })

  lifecycle {
    ignore_changes = [container_definitions]
    # The application repo's deploy workflow updates the image via a new
    # task definition revision. Terraform should not fight it.
  }
}

resource "aws_ecs_service" "main" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  platform_version = "LATEST"

  deployment_minimum_healthy_percent = var.environment == "prod" ? 100 : 0
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = 60

  enable_execute_command = var.environment != "prod"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
    # task_definition is updated by the deploy workflow; desired_count may
    # be adjusted by autoscaling.
  }

  tags = merge(var.tags, { Name = var.service_name })
}
