locals {
  name_prefix = "listings-dev"
  environment = "dev"

  tags = {
    Project     = "listings-api"
    Environment = local.environment
    ManagedBy   = "infra"
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = "10.10.0.0/16"
  az_count           = 2
  single_nat_gateway = true

  tags = local.tags
}

# Names must match exactly what the application requests at runtime
# (shared/secret_store.py in the app repo) - see modules/secrets/main.tf.
module "secrets" {
  source = "../../modules/secrets"

  name_prefix = local.name_prefix
  secret_names = [
    "auth_db_password",
    "auth_db_migrate_password",
    "listing_db_password",
    "listing_db_migrate_password",
    "jwt_secret_key",
  ]

  tags = local.tags
}

module "auth_db" {
  source = "../../modules/database"

  name_prefix           = local.name_prefix
  identifier            = "${local.name_prefix}-auth"
  subnet_ids            = module.network.private_subnet_ids
  security_group_ids    = [module.network.rds_security_group_id]
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  database_name         = "auth"
  environment           = local.environment

  tags = local.tags
}

module "listings_db" {
  source = "../../modules/database"

  name_prefix           = local.name_prefix
  identifier            = "${local.name_prefix}-listings"
  subnet_ids            = module.network.private_subnet_ids
  security_group_ids    = [module.network.rds_security_group_id]
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  database_name         = "listings"
  environment           = local.environment

  tags = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix = local.name_prefix
  repo_names  = ["auth-service", "listings-service"]

  tags = local.tags
}

module "ecs" {
  source = "../../modules/ecs-cluster"

  name_prefix = local.name_prefix
  environment = local.environment

  tags = local.tags
}

# Task roles are scoped per service to only the secrets that service owns.
# The application fetches these directly via boto3 at runtime using its
# task role - see modules/iam/main.tf.
module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix

  services = {
    auth = {
      secret_arns = [
        module.secrets.arns["auth_db_password"],
        module.secrets.arns["auth_db_migrate_password"],
        module.secrets.arns["jwt_secret_key"],
      ]
    }
    listings = {
      secret_arns = [
        module.secrets.arns["listing_db_password"],
        module.secrets.arns["listing_db_migrate_password"],
        module.secrets.arns["jwt_secret_key"],
      ]
    }
  }
  secrets_kms_key_arn = module.secrets.kms_key_arn
  ecr_kms_key_arn     = module.ecr.kms_key_arn

  tags = local.tags
}

module "auth_service" {
  source = "../../modules/service"

  name_prefix        = local.name_prefix
  service_name       = "auth-service"
  cluster_id         = module.ecs.cluster_id
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.tasks_security_group_id]
  container_port     = 8000
  cpu                = 512
  memory             = 1024
  desired_count      = 1
  task_role_arn      = module.iam.task_role_arns["auth"]
  execution_role_arn = module.iam.execution_role_arn
  image_uri          = "${module.ecr.repository_urls["auth-service"]}:bootstrap"
  environment        = local.environment

  # DB_PASSWORD and JWT_SECRET_KEY are deliberately absent: the app reads
  # them from Secrets Manager itself at runtime (see modules/iam), never
  # from an environment variable.
  environment_vars = {
    ENV                         = "production"
    AWS_REGION                  = var.aws_region
    DB_SSL_MODE                 = "require"
    AUTH_DB_HOST                = module.auth_db.address
    AUTH_DB_PORT                = tostring(module.auth_db.port)
    AUTH_DB_NAME                = "auth"
    AUTH_DB_USER                = "auth_rw"
    AUTH_DB_MIGRATE_USER        = "auth_migrate"
    JWT_ALGORITHM               = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES = "30"
    REFRESH_TOKEN_EXPIRE_DAYS   = "7"
    ARGON2_TIME_COST            = "2"
    ARGON2_MEMORY_COST          = "19456"
    ARGON2_PARALLELISM          = "1"
  }

  health_check_path = "/health"

  tags = local.tags
}

module "listings_service" {
  source = "../../modules/service"

  name_prefix        = local.name_prefix
  service_name       = "listings-service"
  cluster_id         = module.ecs.cluster_id
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.tasks_security_group_id]
  container_port     = 8001
  cpu                = 512
  memory             = 1024
  desired_count      = 1
  task_role_arn      = module.iam.task_role_arns["listings"]
  execution_role_arn = module.iam.execution_role_arn
  image_uri          = "${module.ecr.repository_urls["listings-service"]}:bootstrap"
  environment        = local.environment

  environment_vars = {
    ENV                     = "production"
    AWS_REGION              = var.aws_region
    DB_SSL_MODE             = "require"
    LISTING_DB_HOST         = module.listings_db.address
    LISTING_DB_PORT         = tostring(module.listings_db.port)
    LISTING_DB_NAME         = "listings"
    LISTING_DB_USER         = "listing_rw"
    LISTING_DB_MIGRATE_USER = "listing_migrate"
    JWT_ALGORITHM           = "HS256"
  }

  health_check_path = "/health"

  tags = local.tags
}

# Routes mirror gateway/nginx.conf in the app repo (/auth/ -> auth-service,
# /api/ -> listings-service), which the ALB replaces in AWS.
module "alb" {
  source = "../../modules/alb"

  name_prefix        = local.name_prefix
  public_subnet_ids  = module.network.public_subnet_ids
  security_group_ids = [module.network.alb_security_group_id]
  certificate_arn    = var.acm_certificate_arn
  environment        = local.environment

  target_groups = {
    auth = {
      arn           = module.auth_service.target_group_arn
      path_patterns = ["/auth/*"]
      priority      = 10
    }
    listings = {
      arn           = module.listings_service.target_group_arn
      path_patterns = ["/api/*"]
      priority      = 20
    }
  }

  tags = local.tags
}
