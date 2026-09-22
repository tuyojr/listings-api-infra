aws_region = "us-east-1"

# acm_certificate_arn is intentionally not set here - it's account-specific
# and comes from the dev GitHub Environment secret ACM_CERTIFICATE_ARN
# (see .github/workflows/terraform-apply-dev.yml). The variable's own
# default lets `terraform plan` run without it for local/PR review.
