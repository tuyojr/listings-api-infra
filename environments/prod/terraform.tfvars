aws_region = "us-east-1"

# acm_certificate_arn is intentionally not set here - it's account-specific
# and belongs in a prod GitHub Environment secret named ACM_CERTIFICATE_ARN,
# passed via -var on `terraform plan`/`apply` once a prod apply workflow
# exists. The variable's own default lets `terraform plan` run without it
# for local/PR review.
