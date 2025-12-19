# =============================================================================
# Lambda + ECR Container Image - Terraform Configuration
# =============================================================================
# This configuration creates:
# - ECR Repository for Lambda container images
# - Lambda function using container image
# - IAM Role for Lambda execution
# - CloudWatch Log Group for Lambda logs
# - Optional: API Gateway for HTTP invocation
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
# Provider Configuration
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Architecture = "lambda-ecr"
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.id

  common_tags = {
    Name = local.name_prefix
  }
}
