# =============================================================================
# EdgeOS
#
# This config creates:
#   - ECR repositories (3: backend, backoffice, portal)
#   - ECS Cluster + Services + Task Definitions
#   - Application Load Balancer with host-based routing
#
# Everything else (database, S3, secrets, DNS, etc.) is expected to exist
# already. Connection details are passed as plain environment variables.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # URL scheme — https when certificate is present, http otherwise
  scheme = var.certificate_arn != null ? "https" : "http"

  # Resolved storage region — falls back to the main AWS region
  storage_region = var.storage_region != "" ? var.storage_region : var.aws_region

  # Resolved storage endpoint — falls back to AWS S3
  storage_endpoint_url = var.storage_endpoint_url != "" ? var.storage_endpoint_url : "https://s3.${local.storage_region}.amazonaws.com"
}

# =============================================================================
# ECR Repositories
# =============================================================================

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name_prefix}/backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "backoffice" {
  name                 = "${local.name_prefix}/backoffice"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "portal" {
  name                 = "${local.name_prefix}/portal"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backoffice" {
  repository = aws_ecr_repository.backoffice.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "portal" {
  repository = aws_ecr_repository.portal.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}/backend"
  retention_in_days = 30

  tags = { Name = "${local.name_prefix}-backend-logs", Service = "backend" }
}

resource "aws_cloudwatch_log_group" "backoffice" {
  name              = "/ecs/${local.name_prefix}/backoffice"
  retention_in_days = 30

  tags = { Name = "${local.name_prefix}-backoffice-logs", Service = "backoffice" }
}

resource "aws_cloudwatch_log_group" "portal" {
  name              = "/ecs/${local.name_prefix}/portal"
  retention_in_days = 30

  tags = { Name = "${local.name_prefix}-portal-logs", Service = "portal" }
}

# =============================================================================
# IAM — Task Execution Role (pulls images, writes logs)
# =============================================================================

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# IAM — Task Role (application-level permissions)
# =============================================================================

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# =============================================================================
# Security Groups
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Backoffice from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Portal from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-tasks"
  }
}

# =============================================================================
# Application Load Balancer
# =============================================================================

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# HTTP Listener — redirects to HTTPS when certificate is present, otherwise forwards directly
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn != null ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.portal.arn
    }
  }
}

# HTTPS Listener (only created when a certificate is provided)
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn != null ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal.arn
  }
}

# =============================================================================
# Target Groups
# =============================================================================

resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-backend"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health-check"
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-backend", Service = "backend" }
}

resource "aws_lb_target_group" "backoffice" {
  name        = "${local.name_prefix}-backoffice"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-backoffice", Service = "backoffice" }
}

resource "aws_lb_target_group" "portal" {
  name        = "${local.name_prefix}-portal"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-portal", Service = "portal" }
}

# =============================================================================
# Listener Rules — Host-based routing
# Attaches to HTTPS listener when certificate is present, HTTP otherwise.
# =============================================================================

locals {
  active_listener_arn = var.certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = local.active_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = [var.api_domain]
    }
  }
}

resource "aws_lb_listener_rule" "backoffice" {
  listener_arn = local.active_listener_arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backoffice.arn
  }

  condition {
    host_header {
      values = [var.domain]
    }
  }
}

resource "aws_lb_listener_rule" "portal" {
  listener_arn = local.active_listener_arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal.arn
  }

  condition {
    host_header {
      values = ["*.${var.portal_domain}"]
    }
  }
}

# =============================================================================
# Task Definitions
# =============================================================================

# --- Backend ---
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = "${aws_ecr_repository.backend.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "ENVIRONMENT", value = var.environment },
      { name = "PROJECT_NAME", value = var.project_name },
      { name = "BACKOFFICE_URL", value = "${local.scheme}://${var.domain}" },
      { name = "BACKEND_URL", value = "${local.scheme}://${var.api_domain}" },
      { name = "PORTAL_URL", value = "${local.scheme}://${var.portal_domain}" },
      { name = "PORTAL_DOMAIN", value = var.portal_domain },
      { name = "BACKEND_CORS_ORIGINS", value = "${local.scheme}://${var.domain}" },
      { name = "POSTGRES_SERVER", value = var.postgres_server },
      { name = "POSTGRES_PORT", value = var.postgres_port },
      { name = "POSTGRES_DB", value = var.postgres_db },
      { name = "POSTGRES_USER", value = var.postgres_user },
      { name = "POSTGRES_PASSWORD", value = var.postgres_password },
      { name = "POSTGRES_SSL_MODE", value = "require" },
      { name = "SECRET_KEY", value = var.secret_key },
      { name = "SUPERADMIN", value = var.superadmin_email },
      { name = "STORAGE_BUCKET", value = var.storage_bucket },
      { name = "STORAGE_REGION", value = local.storage_region },
      { name = "STORAGE_ENDPOINT_URL", value = local.storage_endpoint_url },
      { name = "STORAGE_ACCESS_KEY", value = var.storage_access_key },
      { name = "STORAGE_SECRET_KEY", value = var.storage_secret_key },
      { name = "STORAGE_PUBLIC_URL", value = var.storage_public_url },
      { name = "SMTP_HOST", value = var.smtp_host },
      { name = "SMTP_PORT", value = var.smtp_port },
      { name = "SMTP_USER", value = var.smtp_user },
      { name = "SMTP_PASSWORD", value = var.smtp_password },
      { name = "SENDER_EMAIL", value = var.sender_email },
      { name = "REDIS_URL", value = var.redis_url },
      { name = "SENTRY_DSN", value = var.sentry_dsn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-backend", Service = "backend" }
}

# --- Prestart (Migrations) ---
resource "aws_ecs_task_definition" "prestart" {
  family                   = "${local.name_prefix}-prestart"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "prestart"
    image     = "${aws_ecr_repository.backend.repository_url}:latest"
    essential = true
    command   = ["bash", "scripts/prestart.sh"]

    environment = [
      { name = "ENVIRONMENT", value = var.environment },
      { name = "PROJECT_NAME", value = var.project_name },
      { name = "POSTGRES_SERVER", value = var.postgres_server },
      { name = "POSTGRES_PORT", value = var.postgres_port },
      { name = "POSTGRES_DB", value = var.postgres_db },
      { name = "POSTGRES_USER", value = var.postgres_user },
      { name = "POSTGRES_PASSWORD", value = var.postgres_password },
      { name = "POSTGRES_SSL_MODE", value = "require" },
      { name = "SECRET_KEY", value = var.secret_key },
      { name = "SUPERADMIN", value = var.superadmin_email },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "prestart"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-prestart", Service = "prestart" }
}

# --- Backoffice ---
resource "aws_ecs_task_definition" "backoffice" {
  family                   = "${local.name_prefix}-backoffice"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "backoffice"
    image     = "${aws_ecr_repository.backoffice.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backoffice.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-backoffice", Service = "backoffice" }
}

# --- Portal ---
resource "aws_ecs_task_definition" "portal" {
  family                   = "${local.name_prefix}-portal"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "portal"
    image     = "${aws_ecr_repository.portal.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "NEXT_PUBLIC_API_URL", value = "${local.scheme}://${var.api_domain}" },
      { name = "ENVIRONMENT", value = var.environment },
      { name = "CUSTOM_DOMAINS_ENABLED", value = "true" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.portal.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-portal", Service = "portal" }
}

# =============================================================================
# ECS Services
# =============================================================================

resource "aws_ecs_service" "backend" {
  name                 = "${local.name_prefix}-backend"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.backend.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = { Name = "${local.name_prefix}-backend", Service = "backend" }
}

resource "aws_ecs_service" "backoffice" {
  name                 = "${local.name_prefix}-backoffice"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.backoffice.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backoffice.arn
    container_name   = "backoffice"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = { Name = "${local.name_prefix}-backoffice", Service = "backoffice" }
}

resource "aws_ecs_service" "portal" {
  name                 = "${local.name_prefix}-portal"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.portal.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.portal.arn
    container_name   = "portal"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = { Name = "${local.name_prefix}-portal", Service = "portal" }
}
