resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-subnet-group" })
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.name_prefix}-pg18"
  family = "postgres18"

  # Enforce SSL for all connections
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Log slow queries (>1s)
  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  # Log all DDL
  parameter {
    name         = "log_statement"
    value        = "ddl"
    apply_method = "immediate"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-pg18" })

  lifecycle { create_before_destroy = true }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.name_prefix}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# The postgres master user only bootstraps the application-level roles
# (auth_rw, auth_migrate, listing_rw, listing_migrate). AWS generates and
# rotates this password automatically; Terraform state holds only the
# Secrets Manager ARN.
resource "aws_db_instance" "main" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = "postgres"

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = var.security_group_ids

  publicly_accessible                 = false
  multi_az                            = var.environment == "prod"
  iam_database_authentication_enabled = true

  backup_retention_period = var.environment == "prod" ? 30 : 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot   = true

  deletion_protection       = var.environment == "prod"
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.identifier}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Free for 7 days of retention on t4g instances - no cost tradeoff to skip.
  performance_insights_enabled = true

  auto_minor_version_upgrade = true
  apply_immediately          = false

  #checkov:skip=CKV_AWS_354:Performance Insights is encrypted at rest by an AWS-owned key by default; a customer-managed key adds operational cost/complexity with no compliance driver here.
  tags = merge(var.tags, { Name = var.identifier })

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}
