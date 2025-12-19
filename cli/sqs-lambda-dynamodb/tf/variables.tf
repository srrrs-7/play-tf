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
  default     = "sqs-lambda-dynamodb"
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
# SQS Settings
# =============================================================================

variable "sqs_visibility_timeout_seconds" {
  description = "SQS visibility timeout (should be >= Lambda timeout)"
  type        = number
  default     = 60
}

variable "sqs_message_retention_seconds" {
  description = "SQS message retention period"
  type        = number
  default     = 345600 # 4 days
}

variable "sqs_max_message_size" {
  description = "SQS max message size in bytes"
  type        = number
  default     = 262144 # 256 KB
}

variable "sqs_delay_seconds" {
  description = "SQS delivery delay"
  type        = number
  default     = 0
}

variable "sqs_receive_wait_time_seconds" {
  description = "SQS receive message wait time (long polling)"
  type        = number
  default     = 20
}

variable "enable_dlq" {
  description = "Enable dead letter queue"
  type        = bool
  default     = true
}

variable "dlq_max_receive_count" {
  description = "Max receive count before moving to DLQ"
  type        = number
  default     = 3
}

variable "enable_fifo_queue" {
  description = "Enable FIFO queue"
  type        = bool
  default     = false
}

variable "fifo_content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO queue"
  type        = bool
  default     = true
}

variable "enable_sqs_encryption" {
  description = "Enable SQS server-side encryption"
  type        = bool
  default     = true
}

# =============================================================================
# Lambda Settings
# =============================================================================

variable "lambda_runtime" {
  description = "Lambda runtime"
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
  description = "Path to Lambda source code directory"
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

variable "lambda_batch_size" {
  description = "Number of records per Lambda invocation"
  type        = number
  default     = 10
}

variable "lambda_max_batching_window" {
  description = "Max batching window in seconds"
  type        = number
  default     = 0
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

variable "dynamodb_range_key" {
  description = "DynamoDB range key name (optional)"
  type        = string
  default     = null
}

variable "dynamodb_range_key_type" {
  description = "DynamoDB range key type"
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

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
