variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the ALB"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the ALB"
}

variable "enable_https" {
  type        = bool
  description = "Create the HTTPS listener and redirect HTTP to it. Set false when no ACM certificate is available yet - the ALB then serves plain HTTP on port 80."
  default     = true
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS. Required when enable_https is true."
  default     = null

  validation {
    condition     = !var.enable_https || var.certificate_arn != null
    error_message = "certificate_arn is required when enable_https is true."
  }
}

variable "elb_log_delivery_account_id" {
  type        = string
  description = "AWS account ID that delivers ALB access logs in this region. This is a fixed, AWS-published value per region (not account-specific) - see https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html"
  default     = "127311923021" # us-east-1
}

variable "environment" {
  type        = string
  description = "Environment name - controls deletion protection and access log retention"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "target_groups" {
  type = map(object({
    arn           = string
    path_patterns = list(string)
    priority      = number
  }))
  description = "Map of service name to its target group ARN and routing rule"
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
