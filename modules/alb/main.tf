data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "prod"

  #checkov:skip=CKV_AWS_144:ALB access logs are regional diagnostic data; cross-region replication is not required.
  #checkov:skip=CKV_AWS_18:Access logging on a log bucket creates a log loop; the ALB delivery itself is the audit trail.
  #checkov:skip=CKV2_AWS_62:Event notifications are not required for a log archive.
  #checkov:skip=CKV_AWS_145:SSE-S3 is sufficient for access logs; KMS would require a key policy for the ELB log delivery account and adds cost.
  #checkov:skip=CKV_AWS_21:access log objects are immutable and unique per delivery, never overwritten; versioning adds storage cost with no corresponding protection here.
  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-logs" })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.environment == "prod" ? 90 : 14
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowALBAccessLogs"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.elb_log_delivery_account_id}:root" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/*"
      },
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.public_subnet_ids

  #checkov:skip=CKV_AWS_150:deletion protection is intentionally environment-gated - dev may still be rebuilt during setup even while temporarily serving production traffic
  #checkov:skip=CKV2_AWS_28:no WAF requirement at this project's current scale; add aws_wafv2_web_acl + association here if that changes
  enable_deletion_protection = var.environment == "prod"
  enable_http2               = true
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "service" {
  for_each = var.target_groups

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = each.value.arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }

  tags = var.tags
}
