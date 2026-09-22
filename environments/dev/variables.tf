variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS on the ALB. Real value comes from the dev GitHub Environment secret ACM_CERTIFICATE_ARN, passed by terraform-apply-dev.yml - this default is a non-resolving placeholder so `terraform plan` works without it."
  default     = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
}
