terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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

# Lambda 関数（署名付き URL 生成）
module "presigned_url_lambda" {
  source = "../../modules/lambda"

  function_name = "${var.project_name}-${var.environment}-presigned-url"
  description   = "Generate presigned URLs for S3 uploads and downloads"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  source_path   = "./s3-presigned-url/dist"
  timeout       = 30
  memory_size   = 256

  environment_variables = {
    BUCKET_NAME        = module.app_bucket.name
    DEFAULT_EXPIRATION = tostring(var.presigned_url_default_expiration)
    ENVIRONMENT        = var.environment
    PROJECT_NAME       = var.project_name
  }

  # S3 への読み取り・書き込み権限
  policy_statements = [
    {
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:PutObjectAcl",
      ]
      resources = [
        "${module.app_bucket.arn}/*"
      ]
    },
    {
      effect = "Allow"
      actions = [
        "s3:ListBucket",
      ]
      resources = [
        module.app_bucket.arn
      ]
    }
  ]

  create_log_group   = true
  log_retention_days = var.lambda_log_retention_days

  tags = {
    Purpose = "Presigned URL Generator"
  }
}

# API Gateway（署名付き URL 払い出し用）
module "presigned_url_api" {
  source = "../../modules/apigateway"

  api_name    = "${var.project_name}-${var.environment}-presigned-url-api"
  description = "API for generating S3 presigned URLs"
  stage_name  = var.environment

  lambda_invoke_arn    = module.presigned_url_lambda.invoke_arn
  lambda_function_name = module.presigned_url_lambda.function_name

  authorization_type   = var.api_authorization_type
  xray_tracing_enabled = var.api_xray_tracing_enabled

  enable_cors       = true
  cors_allow_origin = var.api_cors_allow_origin

  create_log_group   = true
  log_retention_days = var.api_log_retention_days

  tags = {
    Purpose = "Presigned URL API"
  }

  depends_on = [module.presigned_url_lambda]
}
