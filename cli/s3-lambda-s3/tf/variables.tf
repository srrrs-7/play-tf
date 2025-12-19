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
  default     = "s3-lambda-s3"
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
# Source S3 Settings
# =============================================================================

variable "source_bucket_name" {
  description = "Source S3 bucket name (auto-generated if not specified)"
  type        = string
  default     = null
}

variable "source_bucket_force_destroy" {
  description = "Allow source bucket to be destroyed even with objects"
  type        = bool
  default     = false
}

variable "trigger_prefix" {
  description = "S3 key prefix filter for Lambda trigger"
  type        = string
  default     = "input/"
}

variable "trigger_suffix" {
  description = "S3 key suffix filter for Lambda trigger"
  type        = string
  default     = ""
}

variable "trigger_events" {
  description = "S3 event types to trigger Lambda"
  type        = list(string)
  default     = ["s3:ObjectCreated:*"]
}

# =============================================================================
# Destination S3 Settings
# =============================================================================

variable "dest_bucket_name" {
  description = "Destination S3 bucket name (auto-generated if not specified)"
  type        = string
  default     = null
}

variable "dest_bucket_force_destroy" {
  description = "Allow destination bucket to be destroyed even with objects"
  type        = bool
  default     = false
}

variable "dest_prefix" {
  description = "S3 key prefix for output files"
  type        = string
  default     = "output/"
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
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
