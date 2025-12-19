# =============================================================================
# S3 → Lambda → S3 Architecture
# =============================================================================
# Provider Configuration and Data Sources
#
# Architecture:
#   Input S3 Bucket → (Event) → Lambda → Output S3 Bucket
#
# Components:
#   - Source S3 Bucket (input)
#   - Destination S3 Bucket (output)
#   - Lambda Function (processor)
#   - S3 Event Notification
#   - IAM Roles and Policies

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0.0"
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

# =============================================================================
# Locals
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.stack_name}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id

  common_tags = {
    Name = local.name_prefix
  }
}
