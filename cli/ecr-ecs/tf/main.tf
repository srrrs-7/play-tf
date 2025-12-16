# =============================================================================
# ECR → ECS Fargate Architecture
# =============================================================================
# Provider Configuration and Data Sources
#
# Architecture:
#   User → ALB → ECS Fargate (Private Subnet) → ECR
#
# Components:
#   - VPC with public/private subnets (2 AZs)
#   - Internet Gateway + NAT Gateway
#   - ECR Repository
#   - ECS Fargate Cluster + Service
#   - Application Load Balancer
#   - Security Groups (ALB, ECS)
#   - IAM Role (ECS Task Execution)

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# =============================================================================
# Provider
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Stack       = var.stack_name
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# Locals
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.stack_name}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id

  # Use first 2 AZs
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # ECR repository URI
  ecr_repository_url = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/${var.stack_name}"

  common_tags = {
    Name = local.name_prefix
  }
}
