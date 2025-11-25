variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
}

# DynamoDB Variables
variable "table_name" {
  description = "DynamoDB テーブル名のサフィックス"
  type        = string
  default     = "data"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_hash_key" {
  description = "DynamoDB hash (partition) key"
  type        = string
}

variable "dynamodb_range_key" {
  description = "DynamoDB range (sort) key"
  type        = string
  default     = null
}

variable "dynamodb_attributes" {
  description = "DynamoDB attribute definitions"
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

variable "dynamodb_ttl_enabled" {
  description = "Enable TTL for DynamoDB"
  type        = bool
  default     = false
}

variable "dynamodb_ttl_attribute_name" {
  description = "TTL attribute name"
  type        = string
  default     = "ttl"
}

variable "dynamodb_global_secondary_indexes" {
  description = "DynamoDB Global Secondary Indexes"
  type        = list(any)
  default     = []
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery"
  type        = bool
  default     = false
}

variable "dynamodb_stream_enabled" {
  description = "Enable DynamoDB Streams"
  type        = bool
  default     = false
}

variable "dynamodb_stream_view_type" {
  description = "Stream view type"
  type        = string
  default     = null
}

# Lambda Variables
variable "lambda_runtime" {
  description = "Lambda runtime (e.g., python3.11, nodejs20.x)"
  type        = string
  default     = "python3.11"
}

variable "lambda_handler" {
  description = "Lambda handler"
  type        = string
  default     = "index.handler"
}

variable "lambda_source_path" {
  description = "Lambda source code path"
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_architectures" {
  description = "Lambda architectures"
  type        = list(string)
  default     = ["x86_64"]
}

variable "lambda_environment_variables" {
  description = "Additional Lambda environment variables"
  type        = map(string)
  default     = {}
}

variable "lambda_log_retention_days" {
  description = "Lambda log retention in days"
  type        = number
  default     = 7
}

# API Gateway Variables
variable "api_authorization_type" {
  description = "API Gateway authorization type"
  type        = string
  default     = "NONE"
}

variable "api_xray_tracing_enabled" {
  description = "Enable X-Ray tracing for API Gateway"
  type        = bool
  default     = false
}

variable "api_enable_cors" {
  description = "Enable CORS for API Gateway"
  type        = bool
  default     = true
}

variable "api_cors_allow_origin" {
  description = "CORS Allow-Origin header value"
  type        = string
  default     = "'*'"
}

variable "api_log_retention_days" {
  description = "API Gateway log retention in days"
  type        = number
  default     = 7
}

variable "api_stage_variables" {
  description = "API Gateway stage variables"
  type        = map(string)
  default     = {}
}
