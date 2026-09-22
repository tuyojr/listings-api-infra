# Bootstrap

This is used for a one-time setup on each AWS account. It ccreates:

1. S3 bucket for Terraform state
2. KMS key for state encryption
3. GitHub OIDC provider
4. Three IAM roles assumable from GitHub Actions:
    - terraform-plan        (any PR)
    - terraform-apply-dev   (environment: dev)
    - terraform-apply-prod  (environment: prod)

## Prerequisites

- AWS account with admin access
- Access to AWS CloudShell (or an equivalent environment with admin credentials)

**Do not run this from a laptop.** CloudShell provides admin credentials in the browser session; running from a workstation encourages storing long-lived credentials locally.

## Usage

```bash
# Create everything
bash bootstrap/bootstrap.sh -create <github-username>/<repo>

# Tear everything down
bash bootstrap/bootstrap.sh -destroy
```
