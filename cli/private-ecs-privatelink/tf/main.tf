# =============================================================================
# Private ECS with PrivateLink/Direct Connect - Terraform Configuration
# =============================================================================
# This configuration creates a completely closed network environment:
# - VPC with private subnets only (no Internet Gateway or NAT Gateway)
# - VPC Endpoints for AWS services (PrivateLink)
# - ECS Fargate running in private subnets
# - Internal ALB for load balancing
# - VPC Endpoint Service to expose to other VPCs/accounts
# - Transit Gateway for Direct Connect integration
# =============================================================================

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
# Provider Configuration
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Architecture = "private-ecs-privatelink"
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
# Local Variables
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id

  # Use specified AZs or auto-select
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.az_count)

  common_tags = {
    Name = local.name_prefix
  }
}
