# =============================================================================
# EventBridge → Step Functions → Lambda Architecture
# =============================================================================
# イベント駆動型ワークフローオーケストレーション
#
# Architecture:
#   [イベントソース] → [EventBridge] → [Step Functions] → [Lambda A]
#                          ↓                  ↓
#                     [ルールマッチング]   [Lambda B]
#                                             ↓
#                                         [Lambda C]
#
# Components:
#   - EventBridge Event Bus (カスタム)
#   - EventBridge Rule (イベントパターンマッチング)
#   - Step Functions State Machine (ワークフロー)
#   - Lambda Functions (validate, payment, shipping, notify)
#   - IAM Roles (Step Functions, EventBridge, Lambda)

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

  # Lambda関数リスト
  lambda_functions = ["validate", "payment", "shipping", "notify"]
}
