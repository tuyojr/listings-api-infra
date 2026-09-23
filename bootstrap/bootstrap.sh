#!/usr/bin/env bash
#
# This is used for a one-time setup on each AWS account. It ccreates:
#   1. S3 bucket for Terraform state
#   2. KMS key for state encryption
#   3. GitHub OIDC provider
#   4. Three IAM roles assumable from GitHub Actions in the infra repo:
#      - terraform-plan        (any PR)
#      - terraform-apply-dev   (environment: dev)
#      - terraform-apply-prod  (environment: prod)
#   5. Optionally, an app-deploy-dev role (environment: dev) assumable from
#      the app repo's GitHub Actions, for pushing images to ECR and
#      updating the dev ECS services - only created if an app repo is given.
#
# Safe to re-run since every step checks for existence of a resource first.
#
# Run from AWS CloudShell:  bash bootstrap/bootstrap.sh <github-username>/<github-repo>
# The -destroy action is destructive and requires typed confirmation.

set -euo pipefail

usage() {
  cat <<EOF
usage: $0 {-create|-destroy} [<github-username>/<infra-repo>] [<github-username>/<app-repo>]

  -create   Provision the state bucket, KMS key, OIDC provider, and
            IAM roles. Requires the infra repository identifier so the
            terraform-* role trust policies can be scoped to it. If an
            app repository identifier is also given, additionally
            creates an app-deploy-dev role trusted for that repo's
            'dev' GitHub Environment, for pushing to ECR and updating
            the dev ECS services.

  -destroy  Tear down everything this script created. The KMS key is
            scheduled for deletion with the minimum 7-day pending window
            (AWS does not allow immediate key deletion).

  Examples:
    $0 -create  tuyojr/listings-api-infra tuyojr/listings-api
    $0 -destroy
EOF
}

ACTION=""
GITHUB_REPO=""
APP_GITHUB_REPO=""

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
      if [ -z "${GITHUB_REPO}" ]; then
        GITHUB_REPO="$arg"
      elif [ -z "${APP_GITHUB_REPO}" ]; then
        APP_GITHUB_REPO="$arg"
      else
        echo "error: unexpected extra argument: $arg" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "${ACTION}" ]; then
  echo "error: -create or -destroy is required" >&2
  usage >&2
  exit 1
fi

if [ "${ACTION}" = "create" ] && [ -z "${GITHUB_REPO}" ]; then
  echo "error: -create requires <github-username>/<infra-repo>" >&2
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

if [ -n "${APP_GITHUB_REPO}" ]; then
  APP_GITHUB_OWNER="${APP_GITHUB_REPO%%/*}"
  APP_GITHUB_REPO_NAME="${APP_GITHUB_REPO#*/}"
  APP_REPO_PATTERN="${APP_GITHUB_OWNER}@*/${APP_GITHUB_REPO_NAME}@*"
fi

ROLES=(terraform-plan terraform-apply-dev terraform-apply-prod app-deploy-dev)

echo "Account:      ${ACCOUNT_ID}"
echo "Region:       ${AWS_REGION}"
echo "State bucket: ${STATE_BUCKET}"
echo "Action:       ${ACTION}"
[ -n "${GITHUB_REPO}" ] && echo "GitHub repo:  ${GITHUB_REPO}"
echo

create_role() {
  local name="$1"
  local repo="$2"
  local repo_pattern="$3"
  shift 3
  local sub_claims=("$@")
  local trust_policy
  local sub_json
  local repo_json

  sub_json=$(printf '%s\n' "${sub_claims[@]}" | jq -R . | jq -s .)

  repo_json=$(printf '%s\n' "${repo}" "${repo_pattern}" | jq -R . | jq -s .)

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

  create_role "terraform-plan" "${GITHUB_REPO}" "${REPO_PATTERN}" \
    "repo:${REPO_PATTERN}:pull_request" \
    "repo:${REPO_PATTERN}:ref:refs/heads/main" \
    "repo:${REPO_PATTERN}:ref:refs/heads/dev"
  create_role "terraform-apply-dev" "${GITHUB_REPO}" "${REPO_PATTERN}" \
    "repo:${REPO_PATTERN}:environment:dev"
  create_role "terraform-apply-prod" "${GITHUB_REPO}" "${REPO_PATTERN}" \
    "repo:${REPO_PATTERN}:environment:prod"

  if [ -n "${APP_GITHUB_REPO}" ]; then
    create_role "app-deploy-dev" "${APP_GITHUB_REPO}" "${APP_REPO_PATTERN}" \
      "repo:${APP_REPO_PATTERN}:environment:dev"
  else
    echo "*** no app repo given - skipping app-deploy-dev role ***"
  fi

  # The plan role runs on PRs. On a public repo "anyone can open a PR",
  # so this role is deliberately narrow: broad read visibility (for an
  # accurate plan) plus, below, just enough write access to the state
  # backend to take the lock.
  echo "░░ attaching ReadOnlyAccess to terraform-plan ░░"
  aws iam attach-role-policy \
    --role-name terraform-plan \
    --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

  # Even a read-only plan has to take the S3 native state lock, which
  # means writing a .tflock object and using the state bucket's KMS key.
  local state_kms_arn
  state_kms_arn=$(aws kms describe-key --key-id "${KMS_ALIAS}" --query 'KeyMetadata.Arn' --output text)

  put_state_backend_policy() {
    local role_name="$1"
    shift
    local env_prefixes=("$@")
    local resources_json

    resources_json=$(printf '%s\n' "${env_prefixes[@]}" | jq -R \
      --arg bucket "${STATE_BUCKET}" \
      '"arn:aws:s3:::" + $bucket + "/" + . + "/terraform.tfstate*"' | jq -s .)

    echo "░░ putting state-backend policy on ${role_name} (${env_prefixes[*]}) ░░"
    aws iam put-role-policy \
      --role-name "${role_name}" \
      --policy-name "state-backend" \
      --policy-document "$(jq -n \
        --argjson resources "${resources_json}" \
        --arg bucket_arn "arn:aws:s3:::${STATE_BUCKET}" \
        --arg kms_arn "${state_kms_arn}" \
        '{
          Version: "2012-10-17",
          Statement: [
            { Sid: "StateBucketList", Effect: "Allow", Action: "s3:ListBucket", Resource: $bucket_arn },
            { Sid: "StateObjectAccess", Effect: "Allow", Action: ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource: $resources },
            { Sid: "StateKmsAccess", Effect: "Allow", Action: ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"], Resource: $kms_arn }
          ]
        }')"
  }

  put_state_backend_policy "terraform-plan" "dev" "prod"
  put_state_backend_policy "terraform-apply-dev" "dev"
  put_state_backend_policy "terraform-apply-prod" "prod"

  # Resource-management policy for the two apply roles. Scoped to an
  # allow-list of the AWS services our Terraform config actually manages
  echo "░░ putting apply-resources policy on terraform-apply-dev and terraform-apply-prod ░░"
  local apply_policy
  apply_policy=$(jq -n --arg account "${ACCOUNT_ID}" '{
    Version: "2012-10-17",
    Statement: [
      { Sid: "Ec2Full", Effect: "Allow", Action: "ec2:*", Resource: "*" },
      { Sid: "RdsFull", Effect: "Allow", Action: "rds:*", Resource: "*" },
      { Sid: "EcsFull", Effect: "Allow", Action: "ecs:*", Resource: "*" },
      { Sid: "ElbFull", Effect: "Allow", Action: "elasticloadbalancing:*", Resource: "*" },
      { Sid: "SecretsManagerFull", Effect: "Allow", Action: "secretsmanager:*", Resource: "*" },
      { Sid: "KmsFull", Effect: "Allow", Action: "kms:*", Resource: "*" },
      { Sid: "EcrFull", Effect: "Allow", Action: "ecr:*", Resource: "*" },
      { Sid: "LogsFull", Effect: "Allow", Action: "logs:*", Resource: "*" },
      { Sid: "S3ManagedBuckets", Effect: "Allow", Action: "s3:*", Resource: ["arn:aws:s3:::listings-*", "arn:aws:s3:::listings-*/*"] },
      { Sid: "IamRoleManagement", Effect: "Allow", Action: [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
          "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:PassRole"
        ], Resource: ("arn:aws:iam::" + $account + ":role/listings-*") },
      { Sid: "RdsServiceLinkedRole", Effect: "Allow", Action: "iam:CreateServiceLinkedRole",
        Resource: ("arn:aws:iam::" + $account + ":role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"),
        Condition: { StringLike: { "iam:AWSServiceName": "rds.amazonaws.com" } } },
      { Sid: "StsIdentity", Effect: "Allow", Action: "sts:GetCallerIdentity", Resource: "*" }
    ]
  }')

  aws iam put-role-policy --role-name terraform-apply-dev  --policy-name "apply-resources" --policy-document "${apply_policy}"
  aws iam put-role-policy --role-name terraform-apply-prod --policy-name "apply-resources" --policy-document "${apply_policy}"

  # Scoped to exactly what the app repo's CI needs to build and roll out a
  # dev deploy: push images to the two ECR repos, register a new task
  # definition revision for each service, and update the running service.
  # Hardcodes "listings-dev-*" names/families since dev is the only
  # environment with an app-deploy role
  if [ -n "${APP_GITHUB_REPO}" ]; then
    echo "░░ putting deploy-resources policy on app-deploy-dev ░░"
    local deploy_policy
    deploy_policy=$(jq -n --arg region "${AWS_REGION}" --arg account "${ACCOUNT_ID}" '{
      Version: "2012-10-17",
      Statement: [
        { Sid: "EcrAuth", Effect: "Allow", Action: "ecr:GetAuthorizationToken", Resource: "*" },
        { Sid: "EcrPush", Effect: "Allow", Action: [
            "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
            "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"
          ], Resource: [
            ("arn:aws:ecr:" + $region + ":" + $account + ":repository/auth-service"),
            ("arn:aws:ecr:" + $region + ":" + $account + ":repository/listings-service")
          ] },
        { Sid: "EcsRegisterTaskDef", Effect: "Allow", Action: "ecs:RegisterTaskDefinition", Resource: [
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/auth-service:*"),
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/listings-service:*"),
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/listings-dev-db-bootstrap-auth:*"),
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/listings-dev-db-bootstrap-listings:*")
          ] },
        { Sid: "EcsDescribe", Effect: "Allow", Action: [
            "ecs:DescribeTaskDefinition", "ecs:DescribeServices", "ecs:DescribeTasks"
          ], Resource: "*" },
        { Sid: "EcsUpdateService", Effect: "Allow", Action: "ecs:UpdateService",
          Resource: ("arn:aws:ecs:" + $region + ":" + $account + ":service/listings-dev-cluster/*") },
        { Sid: "EcsRunTask", Effect: "Allow", Action: "ecs:RunTask", Resource: [
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/listings-dev-db-bootstrap-auth:*"),
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/listings-dev-db-bootstrap-listings:*"),
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/auth-service:*"),
            ("arn:aws:ecs:" + $region + ":" + $account + ":task-definition/listings-service:*")
          ] },
        { Sid: "DescribeNetworkForRunTask", Effect: "Allow", Action: [
            "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups"
          ], Resource: "*" },
        { Sid: "PassEcsRoles", Effect: "Allow", Action: "iam:PassRole", Resource: [
            ("arn:aws:iam::" + $account + ":role/listings-dev-task-auth"),
            ("arn:aws:iam::" + $account + ":role/listings-dev-task-listings"),
            ("arn:aws:iam::" + $account + ":role/listings-dev-ecs-task-execution"),
            ("arn:aws:iam::" + $account + ":role/listings-dev-task-db-bootstrap-auth"),
            ("arn:aws:iam::" + $account + ":role/listings-dev-task-db-bootstrap-listings")
          ] },
        { Sid: "SecretsWrite", Effect: "Allow", Action: [
            "secretsmanager:PutSecretValue", "secretsmanager:DescribeSecret"
          ], Resource: [
            ("arn:aws:secretsmanager:" + $region + ":" + $account + ":secret:auth_db_password*"),
            ("arn:aws:secretsmanager:" + $region + ":" + $account + ":secret:auth_db_migrate_password*"),
            ("arn:aws:secretsmanager:" + $region + ":" + $account + ":secret:listing_db_password*"),
            ("arn:aws:secretsmanager:" + $region + ":" + $account + ":secret:listing_db_migrate_password*"),
            ("arn:aws:secretsmanager:" + $region + ":" + $account + ":secret:jwt_secret_key*")
          ] },
        { Sid: "SecretsKmsViaSecretsManager", Effect: "Allow", Action: ["kms:GenerateDataKey", "kms:Decrypt"], Resource: "*",
          Condition: { StringEquals: { "kms:ViaService": ("secretsmanager." + $region + ".amazonaws.com") } } }
      ]
    }')

    aws iam put-role-policy --role-name app-deploy-dev --policy-name "deploy-resources" --policy-document "${deploy_policy}"
  fi
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
  echo "dev currently runs the ALB on plain HTTP (no ACM certificate available)."
  echo "When prod gets its own apply workflow, it will need ACM_CERTIFICATE_ARN"
  echo "set as a secret on the 'prod' GitHub Environment."

  if [ -n "${APP_GITHUB_REPO}" ]; then
    echo
    echo "In the app repo (${APP_GITHUB_REPO}), set this as a SECRET on the"
    echo "'dev' GitHub Environment (Settings --> Environments --> dev):"
    echo "-  AWS_DEPLOY_ROLE_ARN     = arn:aws:iam::${ACCOUNT_ID}:role/app-deploy-dev"
    echo
    echo "And this as a repo VARIABLE:"
    echo "-  AWS_REGION              = ${AWS_REGION}"
  fi
fi

if [ "${ACTION}" = "destroy" ]; then
  echo
  echo "=== Teardown complete. ==="
  echo
  echo "KMS key deletion is pending (7 days). No other resources remain."
fi
