data "aws_caller_identity" "current" {}

resource "aws_kms_key" "ecr" {
  description             = "KMS key for ECR repositories (${var.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIamUserPermissions"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecr-kms" })
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repo_names)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.value}" })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = toset(var.repo_names)
  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_tagged_images} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
