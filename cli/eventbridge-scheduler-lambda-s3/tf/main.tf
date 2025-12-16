# =============================================================================
# EventBridge Scheduler → Lambda → S3 Architecture
# =============================================================================
# スケジュール実行によるサーバーレスデータ処理
#
# Architecture:
#   [EventBridge Scheduler] → [Lambda] → [S3]
#          ↓
#     [cron/rate式]
#
# Components:
#   - EventBridge Scheduler (スケジュール実行)
#   - Lambda Function (データ処理)
#   - S3 Bucket (データ保存)
#   - IAM Roles (Scheduler, Lambda)

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
  bucket_name = var.s3_bucket_name != null ? var.s3_bucket_name : "${var.stack_name}-scheduled-data-${local.account_id}"

  common_tags = {
    Name = local.name_prefix
  }
}
