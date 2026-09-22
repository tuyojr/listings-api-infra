variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "repo_names" {
  type        = list(string)
  description = "ECR repository names"
}

variable "untagged_expiry_days" {
  type        = number
  description = "Days before untagged images expire"
  default     = 7
}

variable "max_tagged_images" {
  type        = number
  description = "Number of sha-tagged images to retain"
  default     = 30
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
