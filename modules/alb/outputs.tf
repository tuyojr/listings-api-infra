output "arn" {
  value       = aws_lb.main.arn
  description = "ALB ARN"
}

output "dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB DNS name"
}

output "zone_id" {
  value       = aws_lb.main.zone_id
  description = "ALB Route 53 zone ID (for alias records)"
}

output "https_listener_arn" {
  value       = aws_lb_listener.https.arn
  description = "HTTPS listener ARN"
}
