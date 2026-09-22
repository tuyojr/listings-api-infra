variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. realestate-dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Explicit availability zone names to spread subnets across, e.g. [\"us-east-1a\", \"us-east-1b\"]. Pinned explicitly rather than auto-discovered, so the subnet layout doesn't silently change if AWS adds a new AZ to the region."

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "availability_zones must contain at least 2 zones for subnet/NAT redundancy."
  }
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
