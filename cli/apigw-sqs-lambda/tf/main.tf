# =============================================================================
# API Gateway → SQS → Lambda Architecture
# =============================================================================
# 非同期メッセージ処理アーキテクチャ:
# - API Gatewayが直接SQSにメッセージを送信
# - SQSがバッファとして機能し、スパイクトラフィックを吸収
# - Lambdaがメッセージを処理
# - DLQで失敗メッセージを保持
#
# フロー:
# [Client] → [API Gateway] → [SQS Queue] → [Lambda]
#                                ↓
#                         [Dead Letter Queue]
# =============================================================================

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

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
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
# Local Values
# =============================================================================

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Stack       = var.stack_name
  }
}
