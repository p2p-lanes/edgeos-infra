# =============================================================================
# General
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name (used for resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, production)"
  type        = string
}

# =============================================================================
# Networking (existing VPC)
# =============================================================================

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

# =============================================================================
# Domains & TLS
# =============================================================================

variable "domain" {
  description = "Main domain for backoffice (e.g. app.example.com)"
  type        = string
}

variable "api_domain" {
  description = "API domain for backend (e.g. api.example.com)"
  type        = string
}

variable "portal_domain" {
  description = "Portal domain, supports wildcard subdomains (e.g. portal.example.com)"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate for HTTPS. If null, ALB serves plain HTTP."
  type        = string
  default     = null
}

# =============================================================================
# Backend environment variables
# =============================================================================

variable "postgres_server" {
  description = "PostgreSQL host"
  type        = string
}

variable "postgres_port" {
  description = "PostgreSQL port"
  type        = string
  default     = "5432"
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
}

variable "postgres_user" {
  description = "PostgreSQL user"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "Application secret key (for JWT signing, etc.)"
  type        = string
  sensitive   = true
}

variable "superadmin_email" {
  description = "Superadmin email for initial setup"
  type        = string
  default     = ""
}

variable "smtp_host" {
  description = "SMTP server host"
  type        = string
  default     = ""
}

variable "smtp_port" {
  description = "SMTP server port"
  type        = string
  default     = ""
}

variable "smtp_user" {
  description = "SMTP user"
  type        = string
  default     = ""
}

variable "smtp_password" {
  description = "SMTP password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sender_email" {
  description = "Email sender address"
  type        = string
  default     = ""
}

variable "storage_bucket" {
  description = "S3 bucket name for file storage"
  type        = string
  default     = ""
}

variable "storage_region" {
  description = "S3 bucket region (defaults to aws_region if empty)"
  type        = string
  default     = ""
}

variable "storage_endpoint_url" {
  description = "S3-compatible endpoint URL (leave empty for AWS S3)"
  type        = string
  default     = ""
}

variable "storage_access_key" {
  description = "S3 access key (leave empty to use IAM role)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "storage_secret_key" {
  description = "S3 secret key (leave empty to use IAM role)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "storage_public_url" {
  description = "Public URL for storage (e.g. CDN URL)"
  type        = string
  default     = ""
}

variable "redis_url" {
  description = "Redis connection URL (leave empty to disable)"
  type        = string
  default     = ""
}

variable "sentry_dsn" {
  description = "Sentry DSN for error tracking (leave empty to disable)"
  type        = string
  default     = ""
}
