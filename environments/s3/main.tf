terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# メインアプリケーション用のS3バケット
module "app_bucket" {
  source = "../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-app"
  enable_versioning = true
  enable_lifecycle  = true

  lifecycle_rules = [
    {
      id                                 = "delete-old-versions"
      enabled                            = true
      noncurrent_version_expiration_days = 30
      transitions                        = []
    },
    {
      id              = "transition-to-ia"
      enabled         = true
      expiration_days = null
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        }
      ]
    }
  ]

  tags = {
    Purpose = "Application data"
  }
}
