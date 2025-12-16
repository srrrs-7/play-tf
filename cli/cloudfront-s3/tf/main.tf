# =============================================================================
# CloudFront → S3 Static Website Architecture
# =============================================================================
# 静的ウェブサイトホスティングアーキテクチャ:
# - S3バケットで静的ファイルをホスト
# - CloudFrontでグローバル配信とHTTPS対応
# - OAC (Origin Access Control) でS3への直接アクセスをブロック
#
# フロー:
# [User] → [CloudFront] → [S3 Bucket]
#              ↓
#         [OAC認証]
#
# 注意: OAI (Origin Access Identity) は非推奨のため、OAC を使用
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

  # S3バケット名（指定がない場合は自動生成）
  s3_bucket_name = var.s3_bucket_name != null ? var.s3_bucket_name : "${local.name_prefix}-static-${formatdate("YYYYMMDD", timestamp())}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Stack       = var.stack_name
  }
}
