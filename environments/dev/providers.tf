provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "listings-api"
      Environment = "dev"
      ManagedBy   = "infra"
    }
  }
}
