data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Used by the ECS agent itself to pull the image from ECR and write logs
# to CloudWatch. It does NOT need Secrets Manager access: the application
# fetches its own secrets at runtime (see task roles below), it does not
# use the ECS-native `secrets` container definition field.
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name_prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# AmazonECSTaskExecutionRolePolicy covers the ECR API calls themselves, but
# a CMK-encrypted repository additionally requires kms:Decrypt on the
# execution role or image pulls fail at deploy time.
resource "aws_iam_role_policy" "ecs_task_execution_ecr_kms" {
  name = "ecr-kms-decrypt"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DecryptEcrImages"
      Effect   = "Allow"
      Action   = "kms:Decrypt"
      Resource = var.ecr_kms_key_arn
    }]
  })
}

# This is what the *application code* assumes at runtime. Each service
# calls Secrets Manager directly via boto3, using its task role's
# credentials from the ECS task metadata endpoint. Each role is scoped to only the
# secrets that service owns, so a compromise of one service cannot read
# another's secrets.
resource "aws_iam_role" "task" {
  for_each = var.services

  name = "${var.name_prefix}-task-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "task_secrets" {
  for_each = var.services

  name = "secrets-read"
  role = aws_iam_role.task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOwnSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = each.value.secret_arns
      },
      {
        Sid      = "DecryptSecrets"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.secrets_kms_key_arn
      },
    ]
  })
}

# A separate role for the one-off db-bootstrap task (modules/db_bootstrap),
# not a permission added to aws_iam_role.task above
resource "aws_iam_role" "db_bootstrap_task" {
  for_each = var.db_bootstrap_master_secret_arns

  name = "${var.name_prefix}-task-db-bootstrap-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "db_bootstrap_task_secrets" {
  for_each = var.db_bootstrap_master_secret_arns

  name = "secrets-read"
  role = aws_iam_role.db_bootstrap_task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAppSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = var.services[each.key].secret_arns
      },
      {
        Sid      = "DecryptAppSecrets"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.secrets_kms_key_arn
      },
      {
        Sid    = "ReadMasterSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = each.value
      },
      {
        # The RDS-managed master secret is encrypted with the AWS-owned
        # aws/secretsmanager key
        Sid      = "DecryptMasterSecret"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.region}.amazonaws.com" }
        }
      },
    ]
  })
}
