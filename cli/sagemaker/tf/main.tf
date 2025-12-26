# =============================================================================
# AWS SageMaker Infrastructure
# =============================================================================
# Provider Configuration and Data Sources
#
# Architecture:
#   S3 (Input/Output) -> SageMaker (Training/Processing/Notebooks/Endpoints)
#
# Components:
#   - S3 Buckets (input data, output models, artifacts)
#   - IAM Role (SageMaker execution role)
#   - SageMaker Notebook Instance (optional)
#   - SageMaker Experiment
#   - CloudWatch Log Groups
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

data "aws_partition" "current" {}

# =============================================================================
# Locals
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.stack_name}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id
  partition   = data.aws_partition.current.partition

  # S3 bucket names
  input_bucket_name  = "${var.stack_name}-input-${local.account_id}"
  output_bucket_name = "${var.stack_name}-output-${local.account_id}"
  model_bucket_name  = "${var.stack_name}-models-${local.account_id}"

  common_tags = {
    Name = local.name_prefix
  }
}
