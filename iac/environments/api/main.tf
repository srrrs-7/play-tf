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

# DynamoDB テーブル
module "dynamodb_table" {
  source = "../../modules/dynamodb"

  name         = "${var.project_name}-${var.environment}-${var.table_name}"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = var.dynamodb_hash_key
  range_key    = var.dynamodb_range_key

  attributes = var.dynamodb_attributes

  ttl_enabled        = var.dynamodb_ttl_enabled
  ttl_attribute_name = var.dynamodb_ttl_attribute_name

  global_secondary_indexes = var.dynamodb_global_secondary_indexes

  server_side_encryption_enabled  = true
  point_in_time_recovery_enabled = var.dynamodb_point_in_time_recovery

  stream_enabled   = var.dynamodb_stream_enabled
  stream_view_type = var.dynamodb_stream_view_type

  tags = {
    Purpose = "API Backend Storage"
  }
}

# Lambda 関数
module "lambda_function" {
  source = "../../modules/lambda"

  function_name = "${var.project_name}-${var.environment}-api-handler"
  description   = "API Gateway handler function for ${var.project_name}"
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler
  source_path   = var.lambda_source_path
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  architectures = var.lambda_architectures

  environment_variables = merge(
    var.lambda_environment_variables,
    {
      TABLE_NAME    = module.dynamodb_table.name
      ENVIRONMENT   = var.environment
      PROJECT_NAME  = var.project_name
    }
  )

  # DynamoDBへのアクセス権限
  policy_statements = [
    {
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem"
      ]
      resources = [
        module.dynamodb_table.arn,
        "${module.dynamodb_table.arn}/index/*"
      ]
    }
  ]

  create_log_group    = true
  log_retention_days  = var.lambda_log_retention_days

  tags = {
    Purpose = "API Handler"
  }
}

# API Gateway
module "api_gateway" {
  source = "../../modules/apigateway"

  api_name    = "${var.project_name}-${var.environment}-api"
  description = "REST API for ${var.project_name}"
  stage_name  = var.environment

  lambda_invoke_arn    = module.lambda_function.invoke_arn
  lambda_function_name = module.lambda_function.function_name

  authorization_type   = var.api_authorization_type
  xray_tracing_enabled = var.api_xray_tracing_enabled

  enable_cors       = var.api_enable_cors
  cors_allow_origin = var.api_cors_allow_origin

  create_log_group   = true
  log_retention_days = var.api_log_retention_days

  stage_variables = var.api_stage_variables

  tags = {
    Purpose = "API Gateway"
  }

  depends_on = [module.lambda_function]
}
