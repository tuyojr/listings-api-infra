variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. realestate-dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to spread subnets across"
  default     = 2
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use a single NAT gateway for all AZs (dev). Prod uses one per AZ."
  default     = false
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
