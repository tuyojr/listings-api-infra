variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "execution_role_arn" {
  type        = string
  description = "Shared ECS task execution role ARN (ECR pull + CloudWatch Logs only, no Secrets Manager access)"
}

variable "tasks" {
  description = "Map of service name to its db-bootstrap task config"
  type = map(object({
    task_role_arn     = string
    image_uri         = string
    cpu               = number
    memory            = number
    master_secret_arn = string
    environment_vars  = map(string)
  }))
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
