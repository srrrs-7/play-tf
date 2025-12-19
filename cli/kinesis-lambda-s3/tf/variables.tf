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
  default     = "kinesis-lambda-s3"
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
# Kinesis Settings
# =============================================================================

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 1
}

variable "kinesis_retention_period" {
  description = "Kinesis stream retention period in hours"
  type        = number
  default     = 24
}

variable "kinesis_stream_mode" {
  description = "Kinesis stream capacity mode (PROVISIONED or ON_DEMAND)"
  type        = string
  default     = "PROVISIONED"
}

variable "enable_kinesis_encryption" {
  description = "Enable Kinesis server-side encryption"
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
  default     = 60
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
  default     = 100
}

variable "lambda_starting_position" {
  description = "Kinesis stream starting position (LATEST, TRIM_HORIZON, AT_TIMESTAMP)"
  type        = string
  default     = "LATEST"
}

variable "lambda_max_batching_window" {
  description = "Max batching window in seconds"
  type        = number
  default     = 0
}

variable "lambda_parallelization_factor" {
  description = "Number of batches to process per shard concurrently"
  type        = number
  default     = 1
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda"
  type        = bool
  default     = false
}

# =============================================================================
# S3 Settings
# =============================================================================

variable "s3_bucket_name" {
  description = "S3 bucket name (defaults to stack_name with random suffix)"
  type        = string
  default     = null
}

variable "s3_force_destroy" {
  description = "Allow bucket to be destroyed even with objects"
  type        = bool
  default     = false
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "s3_lifecycle_expire_days" {
  description = "Days until objects expire (0 to disable)"
  type        = number
  default     = 0
}

variable "s3_prefix" {
  description = "S3 key prefix for stored data"
  type        = string
  default     = "data/"
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
