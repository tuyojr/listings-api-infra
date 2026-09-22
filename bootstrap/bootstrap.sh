#!/usr/bin/env bash
#
# This is used for a one-time setup on each AWS account. It ccreates:
#   1. S3 bucket for Terraform state
#   2. KMS key for state encryption
#   3. GitHub OIDC provider
#   4. Three IAM roles assumable from GitHub Actions:
#      - terraform-plan        (any PR)
#      - terraform-apply-dev   (environment: dev)
#      - terraform-apply-prod  (environment: prod)
#
# Safe to re-run since every step checks for existence of a resource first.
#
# Run from AWS CloudShell:  bash bootstrap/bootstrap.sh <github-username>/<github-repo>
# The -destroy action is destructive and requires typed confirmation.

set -euo pipefail

usage() {
  cat <<EOF
usage: $0 {-create|-destroy} [<github-username>/<github-repo>]

  -create   Provision the state bucket, KMS key, OIDC provider, and
            IAM roles. Requires the GitHub repository identifier so the
            role trust policies can be scoped to it.

  -destroy  Tear down everything this script created. The KMS key is
            scheduled for deletion with the minimum 7-day pending window
            (AWS does not allow immediate key deletion).

  Examples:
    $0 -create  tuyojr/listings-api
    $0 -destroy
EOF
}

ACTION=""
GITHUB_REPO=""

for arg in "$@"; do
  case "$arg" in
    -create|--create)   ACTION="create" ;;
    -destroy|--destroy) ACTION="destroy" ;;
    -h|--help|help)     usage; exit 0 ;;
    -*)
      echo "error: unknown flag: $arg" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "${GITHUB_REPO}" ]; then
        echo "error: unexpected extra argument: $arg" >&2
        usage >&2
        exit 1
      fi
      GITHUB_REPO="$arg"
      ;;
  esac
done

if [ -z "${ACTION}" ]; then
  echo "error: -create or -destroy is required" >&2
  usage >&2
  exit 1
fi

if [ "${ACTION}" = "create" ] && [ -z "${GITHUB_REPO}" ]; then
  echo "error: -create requires <github-username>/<repo>" >&2
  usage >&2
  exit 1
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="tfstate-${ACCOUNT_ID}-${AWS_REGION}"
KMS_ALIAS="alias/terraform-state"
OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if [ -n "${GITHUB_REPO}" ]; then
  GITHUB_OWNER="${GITHUB_REPO%%/*}"
  GITHUB_REPO_NAME="${GITHUB_REPO#*/}"
  REPO_PATTERN="${GITHUB_OWNER}@*/${GITHUB_REPO_NAME}@*"
fi

ROLES=(terraform-plan terraform-apply-dev terraform-apply-prod)

echo "Account:      ${ACCOUNT_ID}"
echo "Region:       ${AWS_REGION}"
echo "State bucket: ${STATE_BUCKET}"
echo "Action:       ${ACTION}"
[ -n "${GITHUB_REPO}" ] && echo "GitHub repo:  ${GITHUB_REPO}"
echo

create_role() {
  local name="$1"
  shift
  local sub_claims=("$@")
  local trust_policy
  local sub_json
  local repo_json

  sub_json=$(printf '%s\n' "${sub_claims[@]}" | jq -R . | jq -s .)

  repo_json=$(printf '%s\n' "${GITHUB_REPO}" "${REPO_PATTERN}" | jq -R . | jq -s .)

  trust_policy=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${OIDC_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:repository": ${repo_json},
        "token.actions.githubusercontent.com:sub": ${sub_json}
      }
    }
  }]
}
EOF
)

  if aws iam get-role --role-name "${name}" >/dev/null 2>&1; then
    echo "****** role ${name} exists (updating trust policy) ******"
    aws iam update-assume-role-policy \
      --role-name "${name}" \
      --policy-document "${trust_policy}"
  else
    echo "░░ creating role ${name} ░░"
    aws iam create-role \
      --role-name "${name}" \
      --assume-role-policy-document "${trust_policy}" \
      --max-session-duration 3600 \
      --tags Key=Project,Value=terraform Key=ManagedBy,Value=bootstrap \
      >/dev/null
  fi
}

create() {
  if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    echo "*** state bucket already exists ***"
  else
    echo "░░ creating state bucket ░░"

    local create_args=(
      --bucket "${STATE_BUCKET}"
      --region "${AWS_REGION}"
    )
    if [ "${AWS_REGION}" != "us-east-1" ]; then
      create_args+=(--create-bucket-configuration "LocationConstraint=${AWS_REGION}")
    fi
    aws s3api create-bucket "${create_args[@]}"

    aws s3api put-bucket-versioning \
      --bucket "${STATE_BUCKET}" \
      --versioning-configuration Status=Enabled

    aws s3api put-bucket-encryption \
      --bucket "${STATE_BUCKET}" \
      --server-side-encryption-configuration '{
        "Rules": [{
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "aws:kms",
            "KMSMasterKeyID": "alias/terraform-state"
          },
          "BucketKeyEnabled": true
        }]
      }'

    aws s3api put-public-access-block \
      --bucket "${STATE_BUCKET}" \
      --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    aws s3api put-bucket-policy \
      --bucket "${STATE_BUCKET}" \
      --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyNonTLS",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": [
      "arn:aws:s3:::${STATE_BUCKET}",
      "arn:aws:s3:::${STATE_BUCKET}/*"
    ],
    "Condition": { "Bool": { "aws:SecureTransport": "false" } }
  }]
}
EOF
)"
    echo "==== state bucket created ===="
  fi

  if aws kms describe-key --key-id "${KMS_ALIAS}" >/dev/null 2>&1; then
    echo "*** KMS key already exists ***"
  else
    echo "░░ creating KMS key ░░"

    # We need to capture the key ID directly from create-key output. If we rely
    # on `list-keys`, there's a possibility it returns account-wide keys in unspecified
    # order, and Keys[-1] is not guaranteed to be the one just created.
    local key_id
    key_id=$(aws kms create-key \
      --description "Terraform state encryption" \
      --tags TagKey=Project,TagValue=terraform-state \
      --query 'KeyMetadata.KeyId' \
      --output text)

    aws kms create-alias \
      --alias-name "${KMS_ALIAS}" \
      --target-key-id "${key_id}"

    aws kms enable-key-rotation --key-id "${key_id}"

    echo "==== KMS key created (id=${key_id}) and rotation enabled ===="
  fi

# https://gist.github.com/guitarrapc/8e6b68f21bc1eef8e7b66bde477d5859 here you'd see how the thumbprint was gotten.
# also, AWS stated that they have a list of truster thumbprints that they recognize. https://awscli.amazonaws.com/v2/documentation/api/2.3.2/reference/iam/create-open-id-connect-provider.html#description
# that's why the one below is hardcoded.
  if aws iam list-open-id-connect-providers \
       --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')]" \
       --output text | grep -q .; then
    echo "*** OIDC provider already exists ***"
  else
    echo "░░ creating GitHub OIDC provider ░░"
    aws iam create-open-id-connect-provider \
      --url "${OIDC_URL}" \
      --client-id-list "sts.amazonaws.com" \
      --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
    echo "==== OIDC provider created ===="
  fi

  create_role "terraform-plan" \
    "repo:${REPO_PATTERN}:pull_request" \
    "repo:${REPO_PATTERN}:ref:refs/heads/main" \
    "repo:${REPO_PATTERN}:ref:refs/heads/dev"
  create_role "terraform-apply-dev"  "repo:${REPO_PATTERN}:environment:dev"
  create_role "terraform-apply-prod" "repo:${REPO_PATTERN}:environment:prod"

  # The plan role runs on PRs. On a public repo "anyone can open a PR",
  # so this role is deliberately narrow.
  echo "░░ attaching ReadOnlyAccess to terraform-plan ░░"
  aws iam attach-role-policy \
    --role-name terraform-plan \
    --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
}

destroy() {
  echo "This will permanently destroy:"
  echo "  - IAM roles:   ${ROLES[*]}"
  echo "  - OIDC provider: ${OIDC_ARN}"
  echo "  - S3 bucket:   ${STATE_BUCKET} (and all state files in it)"
  echo "  - KMS key:     ${KMS_ALIAS} (scheduled for deletion, 7-day window)"
  echo
  read -r -p "Type 'destroy' to confirm: " confirm
  if [ "${confirm}" != "destroy" ]; then
    echo "aborted."
    exit 1
  fi
  echo

  for role in "${ROLES[@]}"; do
    if ! aws iam get-role --role-name "${role}" >/dev/null 2>&1; then
      echo "*** role ${role} does not exist (skipping) ***"
      continue
    fi

    echo "░░ deleting role ${role} ░░"

    while IFS= read -r policy_arn; do
      [ -z "${policy_arn}" ] && continue
      aws iam detach-role-policy \
        --role-name "${role}" \
        --policy-arn "${policy_arn}"
    done < <(aws iam list-attached-role-policies \
              --role-name "${role}" \
              --query 'AttachedPolicies[].PolicyArn' \
              --output text | tr '\t' '\n')

    while IFS= read -r policy_name; do
      [ -z "${policy_name}" ] && continue
      aws iam delete-role-policy \
        --role-name "${role}" \
        --policy-name "${policy_name}"
    done < <(aws iam list-role-policies \
              --role-name "${role}" \
              --query 'PolicyNames[]' \
              --output text | tr '\t' '\n')

    aws iam delete-role --role-name "${role}"
    echo "==== role ${role} deleted ===="
  done

  local oidc_to_delete
  oidc_to_delete=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')].Arn" \
    --output text 2>/dev/null || echo "")

  if [ -z "${oidc_to_delete}" ] || [ "${oidc_to_delete}" = "None" ]; then
    echo "*** OIDC provider does not exist (skipping) ***"
  else
    echo "░░ deleting OIDC provider ░░"
    aws iam delete-open-id-connect-provider \
      --open-id-connect-provider-arn "${oidc_to_delete}"
    echo "==== OIDC provider deleted ===="
  fi

  if ! aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    echo "*** state bucket does not exist (skipping) ***"
  else
    echo "░░ emptying state bucket (all versions and delete markers) ░░"

    while IFS=$'\t' read -r key version_id; do
      [ -z "${key:-}" ] && continue
      [ "${key}" = "None" ] && continue
      [ -z "${version_id:-}" ] && continue
      aws s3api delete-object \
        --bucket "${STATE_BUCKET}" \
        --key "${key}" \
        --version-id "${version_id}" \
        >/dev/null
    done < <(aws s3api list-object-versions \
              --bucket "${STATE_BUCKET}" \
              --query 'Versions[].[Key,VersionId]' \
              --output text 2>/dev/null || true)

    while IFS=$'\t' read -r key version_id; do
      [ -z "${key:-}" ] && continue
      [ "${key}" = "None" ] && continue
      [ -z "${version_id:-}" ] && continue
      aws s3api delete-object \
        --bucket "${STATE_BUCKET}" \
        --key "${key}" \
        --version-id "${version_id}" \
        >/dev/null
    done < <(aws s3api list-object-versions \
              --bucket "${STATE_BUCKET}" \
              --query 'DeleteMarkers[].[Key,VersionId]' \
              --output text 2>/dev/null || true)

    echo "░░ deleting state bucket ░░"
    aws s3api delete-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}"
    echo "==== state bucket deleted ===="
  fi

  if ! aws kms describe-key --key-id "${KMS_ALIAS}" >/dev/null 2>&1; then
    echo "*** KMS key does not exist (skipping) ***"
  else
    echo "░░ scheduling KMS key deletion ░░"

    local key_id
    key_id=$(aws kms describe-key \
      --key-id "${KMS_ALIAS}" \
      --query 'KeyMetadata.KeyId' \
      --output text)

    if aws kms list-aliases \
         --query "Aliases[?AliasName=='${KMS_ALIAS}']" \
         --output text | grep -q .; then
      aws kms delete-alias --alias-name "${KMS_ALIAS}"
    fi

    aws kms schedule-key-deletion \
      --key-id "${key_id}" \
      --pending-window-in-days 7

    echo "==== KMS key ${key_id} scheduled for deletion in 7 days ===="
    echo
    echo "To cancel:  aws kms cancel-key-deletion --key-id ${key_id}"
  fi
}

case "${ACTION}" in
  create)  create ;;
  destroy) destroy ;;
esac

if [ "${ACTION}" = "create" ]; then
  echo
  echo "=== Bootstrap complete. ==="
  echo
  echo "Set these as GitHub repo SECRETS (Settings --> Secrets and variables --> Actions --> Secrets):"
  echo "-  TF_STATE_BUCKET        = ${STATE_BUCKET}"
  echo "-  TF_STATE_KMS_KEY       = arn:aws:kms:${AWS_REGION}:${ACCOUNT_ID}:alias/terraform-state"
  echo "-  TF_PLAN_ROLE_ARN       = arn:aws:iam::${ACCOUNT_ID}:role/terraform-plan"
  echo "-  TF_APPLY_DEV_ROLE_ARN  = arn:aws:iam::${ACCOUNT_ID}:role/terraform-apply-dev"
  echo "-  TF_APPLY_PROD_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/terraform-apply-prod"
  echo
  echo "Set this as a GitHub repo VARIABLE (Settings --> Secrets and variables --> Actions --> Variables):"
  echo "-  AWS_REGION             = ${AWS_REGION}"
  echo
  echo "ACM_CERTIFICATE_ARN also needs to be set as a secret on the 'dev' GitHub"
  echo "Environment (Settings --> Environments --> dev), separately from the repo"
  echo "secrets above - it's environment-specific and terraform-apply-dev.yml reads"
  echo "it via that scope."
fi

if [ "${ACTION}" = "destroy" ]; then
  echo
  echo "=== Teardown complete. ==="
  echo
  echo "KMS key deletion is pending (7 days). No other resources remain."
fi
