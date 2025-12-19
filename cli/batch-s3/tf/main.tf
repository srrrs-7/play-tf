# =============================================================================
# AWS Batch → S3 Architecture
# =============================================================================
# Provider Configuration and Data Sources
#
# Architecture:
#   Trigger → AWS Batch Job → S3 (input/output)
#
# Components:
#   - VPC with subnets
#   - AWS Batch Compute Environment
#   - AWS Batch Job Queue
#   - AWS Batch Job Definition
#   - S3 Buckets (input/output)
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
