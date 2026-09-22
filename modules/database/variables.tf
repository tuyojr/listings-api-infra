variable "identifier" {
  type        = string
  description = "RDS instance identifier"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the DB subnet group"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs to attach to the DB instance"
}

variable "database_name" {
  type        = string
  description = "Initial database name"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Initial storage in GB"
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Max storage for storage autoscaling, in GB"
  default     = 100
}

variable "engine_version" {
  type        = string
  description = "Postgres engine version"
  default     = "18.2"
}

variable "environment" {
  type        = string
  description = "Environment name - controls multi_az, backup retention, and deletion protection"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
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
