#!/usr/bin/env bash
# bootstrap/bootstrap.sh
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
# Safe to re-run — every step checks for existence first.
#
# Run from AWS CloudShell:  bash bootstrap/bootstrap.sh <github-org>/<github-repo>

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <github-org>/<github-repo>" >&2
  exit 1
fi

GITHUB_REPO="$1"
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="tfstate-${ACCOUNT_ID}-${AWS_REGION}"
KMS_ALIAS="alias/terraform-state"

echo "Account:     ${ACCOUNT_ID}"
echo "Region:      ${AWS_REGION}"
echo "State bucket: ${STATE_BUCKET}"
echo "GitHub repo: ${GITHUB_REPO}"
echo

if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "*** state bucket already exists ***"
else
  echo "░░ creating state bucket ░░"
  # shellcheck disable=SC2046
  aws s3api create-bucket \
    --bucket "${STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    $([ "${AWS_REGION}" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=${AWS_REGION}")

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
  aws kms create-key \
    --description "Terraform state encryption" \
    --tags TagKey=Project,TagValue=terraform-state \
    >/dev/null
  aws kms create-alias --alias-name "${KMS_ALIAS}" --target-key-id "$(aws kms describe-key --key-id "${KMS_ALIAS}" --query KeyMetadata.KeyId --output text 2>/dev/null || echo)"
  # the "create-alias" needs a key ID, so we need to retrieve it
  KEY_ID=$(aws kms list-keys --query "Keys[-1].KeyId" --output text)
  aws kms create-alias --alias-name "${KMS_ALIAS}" --target-key-id "${KEY_ID}"
  aws kms enable-key-rotation --key-id "${KMS_ALIAS}"
  echo "==== KMS key created and rotation enabled ===="
fi

OIDC_URL="https://token.actions.githubusercontent.com"
if aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')]" --output text | grep -q .; then
  echo "*** OIDC provider already exists ****"
# https://gist.github.com/guitarrapc/8e6b68f21bc1eef8e7b66bde477d5859 here you'd see how the thumbprint was gotten.
# also, AWS stated that they have a list of truster thumbprints that they recognize. https://awscli.amazonaws.com/v2/documentation/api/2.3.2/reference/iam/create-open-id-connect-provider.html#description
# that's why the one below is hardcoded.
else
  echo "░░ creating GitHub OIDC provider ░░"
  aws iam create-open-id-connect-provider \
    --url "${OIDC_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
  echo "=== OIDC provider created ==="
fi

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

create_role() {
  local name="$1"
  local sub_claim="$2"
  local trust_policy
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
        "token.actions.githubusercontent.com:sub": "${sub_claim}"
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
      --tags Key=Project,Key=terraform Key=ManagedBy,Key=bootstrap \
      >/dev/null
  fi
}

create_role "terraform-plan" "repo:${GITHUB_REPO}:pull_request"
create_role "terraform-apply-dev" "repo:${GITHUB_REPO}:environment:dev"
create_role "terraform-apply-prod" "repo:${GITHUB_REPO}:environment:prod"

echo
echo "===Bootstrap complete.==="
echo
echo "Set these as GitHub repo variables (Settings → Variables → Actions):"
echo "  TF_STATE_BUCKET        = ${STATE_BUCKET}"
echo "  TF_STATE_KMS_KEY       = arn:aws:kms:${AWS_REGION}:${ACCOUNT_ID}:alias/terraform-state"
echo "  TF_PLAN_ROLE_ARN       = arn:aws:iam::${ACCOUNT_ID}:role/terraform-plan"
echo "  TF_APPLY_DEV_ROLE_ARN  = arn:aws:iam::${ACCOUNT_ID}:role/terraform-apply-dev"
echo "  TF_APPLY_PROD_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/terraform-apply-prod"
echo
echo "Set AWS_REGION as a variable too: ${AWS_REGION}"
