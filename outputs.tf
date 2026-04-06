# =============================================================================
# ECR
# =============================================================================

output "ecr_backend_url" {
  description = "Backend ECR repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_backoffice_url" {
  description = "Backoffice ECR repository URL"
  value       = aws_ecr_repository.backoffice.repository_url
}

output "ecr_portal_url" {
  description = "Portal ECR repository URL"
  value       = aws_ecr_repository.portal.repository_url
}

# =============================================================================
# ECS
# =============================================================================

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_backend_service_name" {
  description = "Backend ECS service name"
  value       = aws_ecs_service.backend.name
}

output "ecs_backoffice_service_name" {
  description = "Backoffice ECS service name"
  value       = aws_ecs_service.backoffice.name
}

output "ecs_portal_service_name" {
  description = "Portal ECS service name"
  value       = aws_ecs_service.portal.name
}

output "prestart_task_definition" {
  description = "Prestart (migrations) task definition ARN"
  value       = aws_ecs_task_definition.prestart.arn
}

# =============================================================================
# ALB
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS name — create CNAME records pointing your domains here"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias records, if applicable)"
  value       = aws_lb.main.zone_id
}

# =============================================================================
# Security Groups
# =============================================================================

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks — add this to your DB's inbound rules"
  value       = aws_security_group.ecs_tasks.id
}

# =============================================================================
# Deployment helpers
# =============================================================================

output "ecr_login_command" {
  description = "AWS CLI command to authenticate Docker with ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.backend.registry_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "run_migrations_command" {
  description = "AWS CLI command to run database migrations"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.main.name} \
      --task-definition ${aws_ecs_task_definition.prestart.family} \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", var.private_subnet_ids)}],securityGroups=[${aws_security_group.ecs_tasks.id}],assignPublicIp=DISABLED}"
  EOT
}

output "dns_instructions" {
  description = "DNS records to create in your DNS provider"
  value       = <<-EOT
    Create the following CNAME records in your DNS provider:
      ${var.api_domain}        -> ${aws_lb.main.dns_name}
      ${var.domain}            -> ${aws_lb.main.dns_name}
      *.${var.portal_domain}   -> ${aws_lb.main.dns_name}
  EOT
}
