# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a containerized application architecture using ECR, ECS Fargate, and Application Load Balancer. It provides a production-ready setup with private subnets, NAT Gateway, auto-scaling, and CloudWatch logging.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────────────────────┐
│   Users     │ ───▶ │      ALB        │ ───▶ │     Private Subnets (2 AZs)     │
│             │      │   (Public)      │      │  ┌─────────────┐ ┌───────────┐  │
└─────────────┘      └─────────────────┘      │  │  ECS Task   │ │ ECS Task  │  │
                                               │  │  (Fargate)  │ │ (Fargate) │  │
                                               │  └─────────────┘ └───────────┘  │
                                               └─────────────────────────────────┘
                                                              │
                     ┌────────────────────────────────────────┴───────────────────┐
                     │                                                             │
                     ▼                                                             ▼
              ┌─────────────────┐                                    ┌─────────────────┐
              │   NAT Gateway   │                                    │      ECR        │
              │   (for pulls)   │                                    │   Repository    │
              └─────────────────┘                                    └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, availability zones
- `vpc.tf` - VPC, public/private subnets, IGW, NAT Gateway, route tables
- `ecr.tf` - ECR repository with lifecycle policy and image scanning
- `ecs.tf` - ECS cluster, task definition, service, CloudWatch log group
- `alb.tf` - Application Load Balancer, target group, HTTP listener
- `security-groups.tf` - Security groups for ALB and ECS tasks
- `iam.tf` - IAM roles for task execution and task role
- `cloudwatch.tf` - Log group, optional metric filters and alarms
- `variables.tf` - Input variables for VPC, ECR, ECS, and ALB
- `outputs.tf` - ECR repository URL, ALB DNS, ECS cluster ARN

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-app'

# Deploy ECR repository only (first step)
terraform apply -var='stack_name=my-app'

# After pushing image to ECR, create service
terraform apply -var='stack_name=my-app' -var='create_ecs_service=true'

# Destroy
terraform destroy -var='stack_name=my-app'
```

## Deployment Flow

1. VPC with public and private subnets is created
2. NAT Gateway is created for ECR image pulls
3. ECR repository is created with lifecycle policy
4. ECS cluster is created with Fargate capacity providers
5. ALB and target group are created
6. ECS task definition is registered
7. ECS service is created (when `create_ecs_service=true`)

## Push Image to ECR

```bash
# Get ECR login
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin {account-id}.dkr.ecr.ap-northeast-1.amazonaws.com

# Build image
docker build -t {stack_name} .

# Tag image
docker tag {stack_name}:latest {account-id}.dkr.ecr.ap-northeast-1.amazonaws.com/{stack_name}:latest

# Push image
docker push {account-id}.dkr.ecr.ap-northeast-1.amazonaws.com/{stack_name}:latest
```

## Important Notes

- Set `create_ecs_service=false` (default) until image is pushed to ECR
- ECR lifecycle policy keeps last 10 tagged images, deletes untagged after 7 days
- ECS tasks run in private subnets; NAT Gateway required for ECR pulls
- Default Fargate size: 256 CPU units, 512 MB memory
- Target type is `ip` (required for Fargate)
- Circuit breaker is enabled for automatic rollback on deployment failures
- Health check path is `/` by default; customize with `health_check_path`
- Container Insights enabled by default for detailed metrics
- FARGATE_SPOT can be used for cost savings (add via capacity provider strategy)
