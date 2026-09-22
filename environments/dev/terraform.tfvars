aws_region = "us-east-1"

# HTTPS is disabled for dev (modules/alb: enable_https = false in main.tf)
# until an ACM certificate is available - there's no domain to validate one
# against yet. Once there is, set enable_https = true, add back an
# acm_certificate_arn variable sourced from the dev GitHub Environment
# secret ACM_CERTIFICATE_ARN, and restore the plumbing removed from
# terraform-apply-dev.yml.
