# =============================================================================
# ECS on EC2 with Session Manager Architecture
# =============================================================================
# Provider Configuration and Data Sources
#
# Architecture:
#   Session Manager → EC2 (Private Subnet) → Container
#   EC2 → NAT Gateway → Internet (for ECR pull)
#
# Components:
#   - VPC with public/private subnets (2 AZs)
#   - Internet Gateway + NAT Gateway
#   - EC2 instances with ECS-optimized AMI in private subnet
#   - Auto Scaling Group
#   - ECS Cluster (EC2 mode) + Task Definition + Service
#   - IAM Roles (EC2 instance role with ECS+SSM, Task execution role)
#   - Security Group
#   - CloudWatch Logs

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

# ECS-optimized AMI (Amazon Linux 2023)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
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

  # ECS-optimized AMI ID
  ecs_ami_id = data.aws_ssm_parameter.ecs_ami.value

  common_tags = {
    Name = local.name_prefix
  }
}
