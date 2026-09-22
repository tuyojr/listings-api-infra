# Non-sensitive backend config. The bucket, key, and KMS ARN are injected
# by the workflow from GitHub repo variables (see bootstrap/README.md).
# This file exists so `terraform init -backend-config=backend.hcl` works
# locally for plan-only operations, but is not required for CI.
#
# Local usage (plan only, requires AWS creds with read access):
#   terraform init -backend-config=backend.hcl
#
# Do NOT commit real account IDs. Keep the values below as placeholders
# and use the workflow-injected values for anything real.
