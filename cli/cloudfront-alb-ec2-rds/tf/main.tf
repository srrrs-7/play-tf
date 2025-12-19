# =============================================================================
# CloudFront → ALB → EC2 → RDS Architecture (3-tier)
# =============================================================================
# Provider Configuration and Data Sources
#
# Architecture:
#   Users → CloudFront → ALB (Public) → EC2 (Private) → RDS (Private)
#
# Components:
#   - VPC with public/private subnets (2 AZs)
#   - Internet Gateway + NAT Gateway
#   - CloudFront Distribution
#   - Application Load Balancer
#   - EC2 Auto Scaling Group
#   - RDS MySQL/PostgreSQL
#   - Security Groups
#   - IAM Roles

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

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.stack_name}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Name = local.name_prefix
  }
}
