output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "Point your DNS CNAME at this hostname"
}

output "auth_service_ecr_url" {
  value       = module.ecr.repository_urls["auth-service"]
  description = "Auth service ECR repository URL"
}

output "listings_service_ecr_url" {
  value       = module.ecr.repository_urls["listings-service"]
  description = "Listings service ECR repository URL"
}

output "auth_db_endpoint" {
  value       = module.auth_db.address
  description = "Auth RDS endpoint"
}

output "listings_db_endpoint" {
  value       = module.listings_db.address
  description = "Listings RDS endpoint"
}

output "ecs_cluster_name" {
  value       = module.ecs.cluster_name
  description = "ECS cluster name"
}

output "secret_names" {
  value       = module.secrets.names
  description = "Map of secret name to full Secrets Manager name (for out-of-band population)"
}
