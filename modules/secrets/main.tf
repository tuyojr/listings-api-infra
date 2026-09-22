data "aws_caller_identity" "current" {}

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager entries (${var.name_prefix})"
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

  tags = merge(var.tags, { Name = "${var.name_prefix}-secrets-kms" })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Secret containers only - deliberately no aws_secretsmanager_secret_version
# resource. Values are set out-of-band (see bootstrap/README.md) so they
# never enter Terraform state.
#
# Names are NOT prefixed with name_prefix: the application looks these up
# by exact name at runtime (shared/secret_store.py in the app repo), and
# each environment lives in its own AWS account, so there is no
# cross-environment collision.
resource "aws_secretsmanager_secret" "this" {
  for_each = toset(var.secret_names)

  name                    = each.value
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = var.recovery_window_days

  #checkov:skip=CKV2_AWS_57:automatic rotation needs a per-secret Lambda (DB passwords and the JWT signing key each need different rotation logic); out of scope for this build, values are already managed out-of-band
  tags = merge(var.tags, { Name = "${var.name_prefix}-${replace(each.value, "_", "-")}" })
}
