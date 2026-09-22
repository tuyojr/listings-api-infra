variable "name_prefix" {
  type        = string
  description = "Prefix used for the KMS alias and resource tags"
}

variable "secret_names" {
  type        = list(string)
  description = "Exact Secrets Manager secret names to create. Must match the names the application requests at runtime (e.g. auth_db_password, jwt_secret_key) - values are set out-of-band and never enter Terraform state."
}

variable "recovery_window_days" {
  type        = number
  description = "Days a deleted secret can be recovered before permanent deletion"
  default     = 7
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
