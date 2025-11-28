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

# á¤ó¢×ê±ü·çó(nS3Ð±ÃÈ
module "app_bucket" {
  source = "../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-app"
  enable_versioning = true
  enable_lifecycle  = true

  lifecycle_rules = [
    {
      id                                 = "delete-old-versions"
      enabled                            = true
      noncurrent_version_expiration_days = 60
      transitions                        = []
    },
    {
      id              = "transition-to-ia"
      enabled         = true
      expiration_days = null
      transitions = [
        {
          days          = 60
          storage_class = "STANDARD_IA"
        }
      ]
    }
  ]

  tags = {
    Purpose = "Application data"
  }
}

# í°ÝX(nS3Ð±ÃÈ
module "logs_bucket" {
  source = "../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-logs"
  enable_versioning = false
  enable_lifecycle  = true

  lifecycle_rules = [
    {
      id              = "expire-old-logs"
      enabled         = true
      expiration_days = 180
      transitions     = []
    }
  ]

  tags = {
    Purpose = "Application logs"
  }
}

# Y„³óÆóÄ(nS3Ð±ÃÈCORS	¹	
module "static_bucket" {
  source = "../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-static"
  enable_versioning = true

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = var.allowed_origins
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]

  tags = {
    Purpose = "Static content"
  }
}
