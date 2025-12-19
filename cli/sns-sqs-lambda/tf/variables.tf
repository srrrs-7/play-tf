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
  default     = "sns-sqs-lambda"
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
# SNS Settings
# =============================================================================

variable "sns_display_name" {
  description = "SNS topic display name"
  type        = string
  default     = null
}

variable "enable_sns_encryption" {
  description = "Enable SNS server-side encryption"
  type        = bool
  default     = true
}

variable "sns_kms_master_key_id" {
  description = "KMS key ID for SNS encryption (uses alias/aws/sns if not specified)"
  type        = string
  default     = null
}

# =============================================================================
# SQS Settings
# =============================================================================

variable "sqs_visibility_timeout_seconds" {
  description = "SQS visibility timeout"
  type        = number
  default     = 60
}

variable "sqs_message_retention_seconds" {
  description = "SQS message retention period"
  type        = number
  default     = 345600 # 4 days
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

variable "enable_sqs_encryption" {
  description = "Enable SQS server-side encryption"
  type        = bool
  default     = true
}

variable "sns_filter_policy" {
  description = "SNS subscription filter policy (JSON)"
  type        = string
  default     = null
}

variable "raw_message_delivery" {
  description = "Enable raw message delivery (bypass SNS envelope)"
  type        = bool
  default     = false
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

variable "lambda_batch_size" {
  description = "Number of records per Lambda invocation"
  type        = number
  default     = 10
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda"
  type        = bool
  default     = false
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
