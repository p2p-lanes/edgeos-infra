# EdgeOS — ECS Deployment

Terraform configuration that deploys the EdgeOS platform on AWS ECS Fargate with an Application Load Balancer.

## What this creates

- **3 ECR repositories** — container registries for backend, backoffice, and portal images
- **1 ECS cluster** — Fargate-based, with 3 services (one per app)
- **1 Application Load Balancer** — routes traffic to each service by domain (host-header rules)
- **CloudWatch log groups** — centralized logging for all services
- **IAM roles** — task execution and task roles with minimal permissions

## What this does NOT create

Database, S3, Redis, SMTP, DNS records, or certificates. You provide those externally and pass connection details as variables.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2, configured with credentials
- [Docker](https://docs.docker.com/get-docker/)
- An existing AWS VPC with public and private subnets
- A PostgreSQL database accessible from the VPC's private subnets

## Step-by-step setup

### 1. Configure your variables

```bash
cp production.tfvars.example production.tfvars
```

Edit `production.tfvars` and fill in your values. Required fields:

| Variable | Description |
|---|---|
| `vpc_id` | Your existing VPC ID |
| `public_subnet_ids` | Subnets where the ALB will live (must have internet access) |
| `private_subnet_ids` | Subnets where ECS tasks will run (must reach your database) |
| `domain` | Backoffice domain (e.g. `app.example.com`) |
| `api_domain` | API domain (e.g. `api.example.com`) |
| `portal_domain` | Portal domain, supports wildcards (e.g. `portal.example.com`) |
| `postgres_server` | Database host |
| `postgres_db` | Database name |
| `postgres_user` | Database user |
| `postgres_password` | Database password |
| `secret_key` | Application secret (random 64+ char string) |

### 2. Create the ECR repositories first

The ECS services need images to start, but the images need ECR repos to be pushed to. So we create ECR first:

```bash
terraform init
terraform apply -var-file=production.tfvars \
  -target=aws_ecr_repository.backend \
  -target=aws_ecr_repository.backoffice \
  -target=aws_ecr_repository.portal
```

### 3. Build and push the Docker images

Authenticate Docker with ECR:

```bash
aws ecr get-login-password --region <your-region> | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.<your-region>.amazonaws.com
```

Build and push each image (from the application source directories):

```bash
# Backend
docker build -t <ecr_backend_url>:latest -f apps/backend/Dockerfile .
docker push <ecr_backend_url>:latest

# Backoffice
docker build -t <ecr_backoffice_url>:latest -f apps/backoffice/Dockerfile .
docker push <ecr_backoffice_url>:latest

# Portal
docker build -t <ecr_portal_url>:latest -f apps/portal/Dockerfile .
docker push <ecr_portal_url>:latest
```

> Replace `<ecr_*_url>` with the values from `terraform output`.

### 4. Deploy the full infrastructure

```bash
terraform apply -var-file=production.tfvars
```

This creates the ECS cluster, services, ALB, security groups, and IAM roles.

### 5. Allow ECS tasks to reach your database

After apply, Terraform outputs `ecs_tasks_security_group_id`. Add this security group to your database's inbound rules on port 5432.

### 6. Point your domains to the ALB

Terraform outputs `alb_dns_name`. In your DNS provider, create CNAME records:

| Record | Value |
|---|---|
| `api.example.com` | `<alb_dns_name>` |
| `app.example.com` | `<alb_dns_name>` |
| `*.portal.example.com` | `<alb_dns_name>` |

### 7. Run database migrations

```bash
aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --task-definition <project>-<env>-prestart \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_ids>],securityGroups=[<ecs_tasks_security_group_id>],assignPublicIp=DISABLED}"
```

> Terraform outputs `run_migrations_command` with the exact command pre-filled.

## TLS / HTTPS

**Option A — TLS at the ALB (ACM certificate):**

If you have an AWS Certificate Manager certificate, add to your tfvars:

```hcl
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
```

The ALB will terminate TLS and redirect HTTP to HTTPS.

**Option B — TLS at your proxy (e.g. Cloudflare):**

Leave `certificate_arn` out. The ALB serves plain HTTP. Your proxy (Cloudflare, nginx, etc.) handles TLS termination and forwards traffic to the ALB.

## Updating the application

To deploy a new version, push a new image with the `latest` tag and force a new deployment:

```bash
# Build and push the new image
docker build -t <ecr_backend_url>:latest -f apps/backend/Dockerfile .
docker push <ecr_backend_url>:latest

# Force ECS to pull the new image
aws ecs update-service \
  --cluster <ecs_cluster_name> \
  --service <ecs_backend_service_name> \
  --force-new-deployment
```

Repeat for backoffice and portal as needed.

## Useful outputs

After `terraform apply`, run `terraform output` to see:

| Output | Description |
|---|---|
| `alb_dns_name` | ALB address to point your domains to |
| `ecr_backend_url` | ECR URL for the backend image |
| `ecr_backoffice_url` | ECR URL for the backoffice image |
| `ecr_portal_url` | ECR URL for the portal image |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_tasks_security_group_id` | SG to whitelist in your database |
| `ecr_login_command` | Copy-paste Docker login command |
| `run_migrations_command` | Copy-paste migrations command |
| `dns_instructions` | DNS records to create |

## File structure

```
.
├── main.tf                      # All resources (ECR, ECS, ALB, IAM, SGs)
├── variables.tf                 # Input variables
├── outputs.tf                   # Useful outputs and deployment commands
├── versions.tf                  # Terraform and provider versions
└── production.tfvars.example    # Template — copy and fill in your values
```
