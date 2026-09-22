data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  azs = var.availability_zones

  public_subnet_cidrs  = [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # No ingress or egress blocks = deny all traffic.

  tags = merge(var.tags, { Name = "${var.name_prefix}-default-sg-do-not-use" })
}

resource "aws_s3_bucket" "flow_logs" {
  bucket        = "${var.name_prefix}-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  #checkov:skip=CKV_AWS_144:VPC flow logs are regional diagnostic data; cross-region replication is not required.
  #checkov:skip=CKV_AWS_18:Access logging on a log bucket creates a log loop; the flow log itself is the audit trail.
  #checkov:skip=CKV2_AWS_62:Event notifications are not required for a flow log archive.
  #checkov:skip=CKV_AWS_145:SSE-S3 is sufficient for flow logs; KMS would require a key policy for the log delivery service and adds cost.
  #checkov:skip=CKV_AWS_21:flow log objects are immutable and unique per delivery, never overwritten; versioning adds storage cost with no corresponding protection here.
  tags = merge(var.tags, { Name = "${var.name_prefix}-flow-logs" })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket                  = aws_s3_bucket.flow_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-old-flow-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.flow_logs.arn}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.flow_logs.arn
      },
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.flow_logs.arn, "${aws_s3_bucket.flow_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "REJECT"
  log_destination_type     = "s3"
  log_destination          = "${aws_s3_bucket.flow_logs.arn}/vpc-flow-logs"
  max_aggregation_interval = 600

  tags = merge(var.tags, { Name = "${var.name_prefix}-flow-logs" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-${count.index}" })
}

resource "aws_nat_gateway" "main" {
  count         = var.single_nat_gateway ? 1 : length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "${var.name_prefix}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-rt-${count.index}" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )
  tags = merge(var.tags, { Name = "${var.name_prefix}-s3-endpoint" })
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.name_prefix}-endpoints-"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from within VPC"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-endpoints-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "ecr.api",
    "ecr.dkr",
    "secretsmanager",
    "logs",
    "kms",
    "sts",
  ])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${replace(each.value, ".", "-")}-endpoint"
  })
}

# The security groups below are created bare, with every rule added as a
# standalone aws_security_group_rule instead of an inline ingress/egress
# block. Two reasons:
#
#   1. alb, tasks, and rds reference each other's IDs. Terraform can't
#      resolve a cycle where two aws_security_group resources each need
#      the other's id in an inline block, so the cross-references have to
#      be separate resources created after both security groups exist.
#   2. Terraform's aws_security_group resource removes AWS's default
#      "allow all outbound" rule as soon as it manages any rule for that
#      group. A security group with only inline ingress blocks and no
#      egress block ends up with zero egress - not "default allow" - so
#      alb/tasks/rds all need their egress spelled out explicitly or
#      nothing behind them can be reached.

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "ALB - see aws_security_group_rule.alb_* for its rules"
  vpc_id      = aws_vpc.main.id

  #checkov:skip=CKV2_AWS_5:attached via security_group_ids on aws_lb.main in the alb module; cross-module attachment isn't visible to this check
  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "alb_ingress_https" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_ingress_http_redirect" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP for redirect to HTTPS"

  #checkov:skip=CKV_AWS_260:port 80 must be reachable for the HTTP->HTTPS 301 redirect; the ALB listener does no other work on 80
}

resource "aws_security_group_rule" "alb_egress_to_tasks" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  from_port                = 8000
  to_port                  = 8001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.tasks.id
  description              = "Forward requests to ECS tasks"
}

resource "aws_security_group" "tasks" {
  name_prefix = "${var.name_prefix}-tasks-"
  description = "ECS tasks - see aws_security_group_rule.tasks_* for its rules"
  vpc_id      = aws_vpc.main.id

  #checkov:skip=CKV2_AWS_5:attached via security_group_ids on aws_ecs_service.main in the service module; cross-module attachment isn't visible to this check
  tags = merge(var.tags, { Name = "${var.name_prefix}-tasks-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "tasks_ingress_from_alb" {
  security_group_id        = aws_security_group.tasks.id
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "App ports from ALB"
}

resource "aws_security_group_rule" "tasks_egress_to_rds" {
  security_group_id        = aws_security_group.tasks.id
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  description              = "Postgres to RDS"
}

resource "aws_security_group_rule" "tasks_egress_to_endpoints" {
  security_group_id        = aws_security_group.tasks.id
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.endpoints.id
  description              = "HTTPS to ECR, Secrets Manager, KMS, CloudWatch Logs, and STS via VPC endpoints"
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "RDS - see aws_security_group_rule.rds_* for its rules"
  vpc_id      = aws_vpc.main.id

  #checkov:skip=CKV2_AWS_5:attached via vpc_security_group_ids on aws_db_instance.main in the database module; cross-module attachment isn't visible to this check
  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "rds_ingress_from_tasks" {
  security_group_id        = aws_security_group.rds.id
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.tasks.id
  description              = "Postgres from ECS tasks"
}
