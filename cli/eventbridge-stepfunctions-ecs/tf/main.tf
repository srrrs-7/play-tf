# =============================================================================
# EventBridge → Step Functions → ECS Tasks Architecture
# =============================================================================
# イベント駆動型コンテナタスクオーケストレーション
#
# Architecture:
#   [イベントソース] → [EventBridge] → [Step Functions] → [ECS Task A]
#                                              ↓
#                                         [ECS Task B]
#                                              ↓
#                                         [ECS Task C]
#
# Components:
#   - EventBridge Event Bus (カスタム)
#   - EventBridge Rule (イベントパターンマッチング)
#   - Step Functions State Machine (ワークフロー)
#   - ECS Cluster (Fargate)
#   - ECS Task Definition
#   - IAM Roles (Step Functions, EventBridge, ECS)
#   - VPC (オプション：既存または新規作成)

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

# デフォルトVPCを使用する場合
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

data "aws_security_group" "default" {
  count  = var.use_default_vpc ? 1 : 0
  vpc_id = data.aws_vpc.default[0].id
  name   = "default"
}

# =============================================================================
# Locals
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.stack_name}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id

  # VPCとサブネットの選択
  vpc_id = var.use_default_vpc ? data.aws_vpc.default[0].id : aws_vpc.main[0].id
  subnet_ids = var.use_default_vpc ? slice(data.aws_subnets.default[0].ids, 0, min(2, length(data.aws_subnets.default[0].ids))) : aws_subnet.public[*].id
  security_group_id = var.use_default_vpc ? data.aws_security_group.default[0].id : aws_security_group.ecs[0].id

  # AZs
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Name = local.name_prefix
  }
}
