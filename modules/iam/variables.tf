variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "services" {
  type = map(object({
    secret_arns = list(string)
  }))
  description = "Map of service name to the Secrets Manager ARNs its task role may read"
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt the secrets referenced in var.services - granted kms:Decrypt on each task role"
}

variable "db_bootstrap_master_secret_arns" {
  type        = map(string)
  description = "Map of service name to the RDS-managed master secret ARN for its database. Granted only to a dedicated db-bootstrap task role per key, never to the regular task role in var.services."
  default     = {}
}

variable "ecr_kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt the ECR repositories - granted kms:Decrypt on the execution role, required for ECS to pull CMK-encrypted images"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default = {
    ManagedBy   = "infra"
    Environment = "dev"
    Project     = "listings-api"
  }
}
