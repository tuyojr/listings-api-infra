variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "service_name" {
  type        = string
  description = "Name of the service (e.g. auth-service)"
}

variable "cluster_id" {
  type        = string
  description = "ECS cluster ID"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the service tasks"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the service tasks"
}

variable "container_port" {
  type        = number
  description = "Port the container listens on"
}

variable "cpu" {
  type        = number
  description = "Task CPU units"
}

variable "memory" {
  type        = number
  description = "Task memory in MB"
}

variable "desired_count" {
  type        = number
  description = "Desired number of tasks"
}

variable "task_role_arn" {
  type        = string
  description = "Task role ARN - the application assumes this at runtime to read its own secrets"
}

variable "execution_role_arn" {
  type        = string
  description = "Task execution role ARN"
}

variable "image_uri" {
  type        = string
  description = "Container image URI"
}

variable "environment" {
  type        = string
  description = "Environment name - controls deployment_minimum_healthy_percent, log retention, and ECS exec access"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "environment_vars" {
  type        = map(string)
  description = "Non-sensitive environment variables. Secrets are fetched by the application itself at runtime via its task role - see modules/iam - not injected here."
  default     = {}
}

variable "health_check_path" {
  type        = string
  description = "HTTP path for the ALB target group and container health checks"
  default     = "/health"
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
