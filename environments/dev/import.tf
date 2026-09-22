# One-time reconciliation after the Terraform state bucket was accidentally
# destroyed and recreated empty. Every resource below already existed in
# AWS from prior applies; these blocks re-attach them to state instead of
# letting apply try to create duplicates or fail on AlreadyExists. Safe to
# remove once terraform apply has run successfully with these in place -
# re-running an already-satisfied import is a no-op.

import {
  to = module.network.aws_vpc.main
  id = "vpc-0115ee99c7ceeda45"
}

import {
  to = module.network.aws_default_security_group.default
  id = "sg-0bae87923635020e2"
}

import {
  to = module.network.aws_s3_bucket.flow_logs
  id = "listings-dev-flow-logs-603227569238"
}

import {
  to = module.network.aws_s3_bucket_public_access_block.flow_logs
  id = "listings-dev-flow-logs-603227569238"
}

import {
  to = module.network.aws_s3_bucket_server_side_encryption_configuration.flow_logs
  id = "listings-dev-flow-logs-603227569238"
}

import {
  to = module.network.aws_s3_bucket_lifecycle_configuration.flow_logs
  id = "listings-dev-flow-logs-603227569238"
}

import {
  to = module.network.aws_s3_bucket_policy.flow_logs
  id = "listings-dev-flow-logs-603227569238"
}

import {
  to = module.network.aws_flow_log.main
  id = "fl-0c9623d76a5d598dc"
}

import {
  to = module.network.aws_internet_gateway.main
  id = "igw-0b32e95ae9d37d6a2"
}

# count-based resources can't use for_each/each.key on the import block
# (Terraform requires the target itself to use for_each for that) - each
# instance needs its own block with a literal index.
import {
  to = module.network.aws_subnet.public[0]
  id = "subnet-0a996c7037c1744f9" # us-east-1a
}

import {
  to = module.network.aws_subnet.public[1]
  id = "subnet-0eeb04f9f48a9f5ee" # us-east-1b
}

import {
  to = module.network.aws_subnet.private[0]
  id = "subnet-0022ffcbcef58e7d4" # us-east-1a
}

import {
  to = module.network.aws_subnet.private[1]
  id = "subnet-02458f62c976d5c21" # us-east-1b
}

import {
  to = module.network.aws_eip.nat[0]
  id = "eipalloc-0d86d218929f1c720"
}

import {
  to = module.network.aws_nat_gateway.main[0]
  id = "nat-078e66af2c3314999"
}

import {
  to = module.network.aws_route_table.public
  id = "rtb-01a61f41053607047"
}

import {
  to = module.network.aws_route_table_association.public[0]
  id = "subnet-0a996c7037c1744f9/rtb-01a61f41053607047"
}

import {
  to = module.network.aws_route_table_association.public[1]
  id = "subnet-0eeb04f9f48a9f5ee/rtb-01a61f41053607047"
}

import {
  to = module.network.aws_route_table.private[0]
  id = "rtb-06bc72c1f52ca9137"
}

import {
  to = module.network.aws_route_table_association.private[0]
  id = "subnet-0022ffcbcef58e7d4/rtb-06bc72c1f52ca9137"
}

import {
  to = module.network.aws_route_table_association.private[1]
  id = "subnet-02458f62c976d5c21/rtb-06bc72c1f52ca9137"
}

import {
  to = module.network.aws_vpc_endpoint.s3
  id = "vpce-0e40d2a5b98a54222"
}

import {
  to = module.network.aws_security_group.endpoints
  id = "sg-0b3d3626ff36ee3f6"
}

import {
  for_each = {
    "ecr.api"        = "vpce-06ca99772d58958d9"
    "ecr.dkr"        = "vpce-0348cbe6b1295bbb5"
    "secretsmanager" = "vpce-0d802738cdc2573c2"
    "logs"           = "vpce-093e734d0cf47c9c5"
    "kms"            = "vpce-0aab07c9393c20071"
    "sts"            = "vpce-036de36787bfb45ea"
  }
  to = module.network.aws_vpc_endpoint.interface[each.key]
  id = each.value
}

import {
  to = module.network.aws_security_group.alb
  id = "sg-090894eb00bc40929"
}

import {
  to = module.network.aws_security_group_rule.alb_ingress_https
  id = "sg-090894eb00bc40929_ingress_tcp_443_443_0.0.0.0/0"
}

import {
  to = module.network.aws_security_group_rule.alb_ingress_http_redirect
  id = "sg-090894eb00bc40929_ingress_tcp_80_80_0.0.0.0/0"
}

import {
  to = module.network.aws_security_group_rule.alb_egress_to_tasks
  id = "sg-090894eb00bc40929_egress_tcp_8000_8001_sg-08f444ad67becbcc6"
}

import {
  to = module.network.aws_security_group.tasks
  id = "sg-08f444ad67becbcc6"
}

import {
  to = module.network.aws_security_group_rule.tasks_ingress_from_alb
  id = "sg-08f444ad67becbcc6_ingress_tcp_8000_8001_sg-090894eb00bc40929"
}

import {
  to = module.network.aws_security_group_rule.tasks_egress_to_rds
  id = "sg-08f444ad67becbcc6_egress_tcp_5432_5432_sg-02da9b3a40d427b20"
}

import {
  to = module.network.aws_security_group_rule.tasks_egress_to_endpoints
  id = "sg-08f444ad67becbcc6_egress_tcp_443_443_sg-0b3d3626ff36ee3f6"
}

import {
  to = module.network.aws_security_group.rds
  id = "sg-02da9b3a40d427b20"
}

import {
  to = module.network.aws_security_group_rule.rds_ingress_from_tasks
  id = "sg-02da9b3a40d427b20_ingress_tcp_5432_5432_sg-08f444ad67becbcc6"
}

# module.secrets
import {
  to = module.secrets.aws_kms_key.secrets
  id = "c56ae198-6577-4004-ba31-efe033b95ab8"
}

import {
  to = module.secrets.aws_kms_alias.secrets
  id = "alias/listings-dev-secrets"
}

import {
  for_each = {
    "auth_db_password"            = "arn:aws:secretsmanager:us-east-1:603227569238:secret:auth_db_password-bX5lA8"
    "auth_db_migrate_password"    = "arn:aws:secretsmanager:us-east-1:603227569238:secret:auth_db_migrate_password-ONs7G5"
    "listing_db_password"         = "arn:aws:secretsmanager:us-east-1:603227569238:secret:listing_db_password-CTog2B"
    "listing_db_migrate_password" = "arn:aws:secretsmanager:us-east-1:603227569238:secret:listing_db_migrate_password-KIQ5cZ"
    "jwt_secret_key"              = "arn:aws:secretsmanager:us-east-1:603227569238:secret:jwt_secret_key-JE0Iis"
  }
  to = module.secrets.aws_secretsmanager_secret.this[each.key]
  id = each.value
}

# module.auth_db
import {
  to = module.auth_db.aws_db_subnet_group.main
  id = "listings-dev-auth-subnet-group"
}

import {
  to = module.auth_db.aws_db_parameter_group.main
  id = "listings-dev-auth-pg18"
}

import {
  to = module.auth_db.aws_iam_role.rds_monitoring
  id = "listings-dev-auth-rds-monitoring"
}

import {
  to = module.auth_db.aws_iam_role_policy_attachment.rds_monitoring
  id = "listings-dev-auth-rds-monitoring/arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# module.listings_db
import {
  to = module.listings_db.aws_db_subnet_group.main
  id = "listings-dev-listings-subnet-group"
}

import {
  to = module.listings_db.aws_db_parameter_group.main
  id = "listings-dev-listings-pg18"
}

import {
  to = module.listings_db.aws_iam_role.rds_monitoring
  id = "listings-dev-listings-rds-monitoring"
}

import {
  to = module.listings_db.aws_iam_role_policy_attachment.rds_monitoring
  id = "listings-dev-listings-rds-monitoring/arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# module.ecr
import {
  to = module.ecr.aws_kms_key.ecr
  id = "3b2774c8-f42a-4603-9c46-c4b7fb733894"
}

import {
  for_each = toset(["auth-service", "listings-service"])
  to       = module.ecr.aws_ecr_repository.this[each.key]
  id       = each.value
}

import {
  for_each = toset(["auth-service", "listings-service"])
  to       = module.ecr.aws_ecr_lifecycle_policy.this[each.key]
  id       = each.value
}

# module.ecs
import {
  to = module.ecs.aws_cloudwatch_log_group.exec
  id = "/aws/ecs/listings-dev/exec"
}

import {
  to = module.ecs.aws_ecs_cluster.main
  id = "listings-dev-cluster"
}

import {
  to = module.ecs.aws_ecs_cluster_capacity_providers.main
  id = "listings-dev-cluster"
}

# module.iam
import {
  to = module.iam.aws_iam_role.ecs_task_execution
  id = "listings-dev-ecs-task-execution"
}

import {
  to = module.iam.aws_iam_role_policy_attachment.ecs_task_execution_managed
  id = "listings-dev-ecs-task-execution/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

import {
  to = module.iam.aws_iam_role_policy.ecs_task_execution_ecr_kms
  id = "listings-dev-ecs-task-execution:ecr-kms-decrypt"
}

import {
  for_each = {
    "auth"     = "listings-dev-task-auth"
    "listings" = "listings-dev-task-listings"
  }
  to = module.iam.aws_iam_role.task[each.key]
  id = each.value
}

import {
  for_each = {
    "auth"     = "listings-dev-task-auth:secrets-read"
    "listings" = "listings-dev-task-listings:secrets-read"
  }
  to = module.iam.aws_iam_role_policy.task_secrets[each.key]
  id = each.value
}

# module.auth_service
import {
  to = module.auth_service.aws_cloudwatch_log_group.main
  id = "/ecs/listings-dev/auth-service"
}

import {
  to = module.auth_service.aws_lb_target_group.main
  id = "arn:aws:elasticloadbalancing:us-east-1:603227569238:targetgroup/listings-dev-auth-service-tg/73ff01955028566d"
}

# module.listings_service
import {
  to = module.listings_service.aws_cloudwatch_log_group.main
  id = "/ecs/listings-dev/listings-service"
}

import {
  to = module.listings_service.aws_lb_target_group.main
  id = "arn:aws:elasticloadbalancing:us-east-1:603227569238:targetgroup/listings-dev-listings-service-tg/2aff0d668932e560"
}

# module.alb
import {
  to = module.alb.aws_s3_bucket.logs
  id = "listings-dev-alb-logs-603227569238"
}

import {
  to = module.alb.aws_s3_bucket_public_access_block.logs
  id = "listings-dev-alb-logs-603227569238"
}

import {
  to = module.alb.aws_s3_bucket_server_side_encryption_configuration.logs
  id = "listings-dev-alb-logs-603227569238"
}

import {
  to = module.alb.aws_s3_bucket_lifecycle_configuration.logs
  id = "listings-dev-alb-logs-603227569238"
}

import {
  to = module.alb.aws_s3_bucket_policy.logs
  id = "listings-dev-alb-logs-603227569238"
}

import {
  to = module.alb.aws_lb.main
  id = "arn:aws:elasticloadbalancing:us-east-1:603227569238:loadbalancer/app/listings-dev-alb/0de70e4af83be032"
}

import {
  to = module.alb.aws_lb_listener.http[0]
  id = "arn:aws:elasticloadbalancing:us-east-1:603227569238:listener/app/listings-dev-alb/0de70e4af83be032/c57cc34067b93128"
}

import {
  for_each = {
    "auth"     = "arn:aws:elasticloadbalancing:us-east-1:603227569238:listener-rule/app/listings-dev-alb/0de70e4af83be032/c57cc34067b93128/0eb69780e8495cc5"
    "listings" = "arn:aws:elasticloadbalancing:us-east-1:603227569238:listener-rule/app/listings-dev-alb/0de70e4af83be032/c57cc34067b93128/9f4282c3e5fa0f73"
  }
  to = module.alb.aws_lb_listener_rule.service[each.key]
  id = each.value
}
