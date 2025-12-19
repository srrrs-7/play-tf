# =============================================================================
# General Settings
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "apigw-lambda-dynamodb"
}

variable "environment" {
  description = "Environment name (dev, stg, prd)"
  type        = string
  default     = "dev"
}

variable "stack_name" {
  description = "Stack name for resource identification (required)"
  type        = string
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# API Gateway Settings
# =============================================================================

variable "api_name" {
  description = "API Gateway name (defaults to stack_name)"
  type        = string
  default     = null
}

variable "api_description" {
  description = "API Gateway description"
  type        = string
  default     = "REST API for Lambda-DynamoDB integration"
}

variable "api_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "v1"
}

variable "enable_cors" {
  description = "Enable CORS support"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "CORS allowed methods"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "CORS allowed headers"
  type        = list(string)
  default     = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]
}

variable "enable_api_key" {
  description = "Enable API key authentication"
  type        = bool
  default     = false
}

variable "throttling_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 100
}

variable "throttling_rate_limit" {
  description = "API Gateway throttling rate limit"
  type        = number
  default     = 50
}

# =============================================================================
# Lambda Settings
# =============================================================================

variable "lambda_runtime" {
  description = "Lambda runtime (python3.11, nodejs18.x, etc.)"
  type        = string
  default     = "python3.11"
}

variable "lambda_handler" {
  description = "Lambda handler function"
  type        = string
  default     = "index.handler"
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_source_path" {
  description = "Path to Lambda source code directory (optional, uses inline code if not provided)"
  type        = string
  default     = null
}

variable "lambda_environment_variables" {
  description = "Additional Lambda environment variables"
  type        = map(string)
  default     = {}
}

variable "lambda_reserved_concurrency" {
  description = "Lambda reserved concurrent executions (-1 for no limit)"
  type        = number
  default     = -1
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda"
  type        = bool
  default     = false
}

# =============================================================================
# DynamoDB Settings
# =============================================================================

variable "dynamodb_table_name" {
  description = "DynamoDB table name (defaults to stack_name)"
  type        = string
  default     = null
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (for PROVISIONED billing)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (for PROVISIONED billing)"
  type        = number
  default     = 5
}

variable "dynamodb_hash_key" {
  description = "DynamoDB hash key name"
  type        = string
  default     = "id"
}

variable "dynamodb_hash_key_type" {
  description = "DynamoDB hash key type (S, N, or B)"
  type        = string
  default     = "S"
}

variable "dynamodb_range_key" {
  description = "DynamoDB range key name (optional)"
  type        = string
  default     = null
}

variable "dynamodb_range_key_type" {
  description = "DynamoDB range key type (S, N, or B)"
  type        = string
  default     = "S"
}

variable "dynamodb_enable_ttl" {
  description = "Enable TTL on DynamoDB table"
  type        = bool
  default     = false
}

variable "dynamodb_ttl_attribute" {
  description = "DynamoDB TTL attribute name"
  type        = string
  default     = "ttl"
}

variable "dynamodb_enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB"
  type        = bool
  default     = false
}

variable "dynamodb_global_secondary_indexes" {
  description = "DynamoDB global secondary indexes"
  type = list(object({
    name               = string
    hash_key           = string
    hash_key_type      = string
    range_key          = optional(string)
    range_key_type     = optional(string)
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string), [])
  }))
  default = []
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway CloudWatch logging"
  type        = bool
  default     = true
}
