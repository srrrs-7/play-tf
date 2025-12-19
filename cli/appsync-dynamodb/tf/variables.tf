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
  default     = "appsync-dynamodb"
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
# AppSync Settings
# =============================================================================

variable "authentication_type" {
  description = "AppSync authentication type (API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT)"
  type        = string
  default     = "API_KEY"
}

variable "api_key_expires_days" {
  description = "API key expiration in days (max 365)"
  type        = number
  default     = 7
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for AppSync"
  type        = bool
  default     = false
}

variable "log_level" {
  description = "AppSync logging level (NONE, ERROR, ALL)"
  type        = string
  default     = "ERROR"
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
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
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

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
