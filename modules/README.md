# Modules

Reusable building blocks consumed by `environments/dev` and `environments/prod`. Each module is self-contained (own `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`) and has no backend or provider configuration of its own.

| Module | Creates |
| --- | --- |
| `network` | VPC, public/private subnets, NAT, VPC flow logs, S3/interface endpoints, security groups (ALB, ECS tasks, RDS, endpoints) |
| `secrets` | KMS key + Secrets Manager containers (values set out-of-band, never in state) |
| `database` | RDS Postgres instance, subnet group, parameter group, enhanced monitoring role |
| `iam` | Shared ECS task execution role, one task role per service scoped to its own secrets |
| `ecr` | ECR repositories with KMS encryption, scan-on-push, and lifecycle policies |
| `ecs-cluster` | ECS cluster with Fargate/Fargate Spot capacity providers |
| `alb` | Application Load Balancer, HTTPS listener, path-based routing rules, access log bucket |
| `service` | ECS task definition + service + target group + log group for one service |

Security group rules that cross between `alb`, `tasks`, and `rds` are all defined in `network` as standalone `aws_security_group_rule` resources rather than inline blocks - see the comment above those resources in `network/main.tf` for why.
