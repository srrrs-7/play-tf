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
  default     = "eb-scheduler"
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
# EventBridge Scheduler Settings
# =============================================================================

variable "schedule_expression" {
  description = "Schedule expression (e.g., 'rate(5 minutes)' or 'cron(0 12 * * ? *)')"
  type        = string
  default     = "rate(5 minutes)"
}

variable "schedule_enabled" {
  description = "Whether the schedule is enabled"
  type        = bool
  default     = true
}

variable "schedule_timezone" {
  description = "Timezone for cron expressions (e.g., 'Asia/Tokyo')"
  type        = string
  default     = "UTC"
}

variable "flexible_time_window_minutes" {
  description = "Flexible time window in minutes (0 for OFF)"
  type        = number
  default     = 0
}

# =============================================================================
# Lambda Settings
# =============================================================================

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_source_path" {
  description = "Path to Lambda source code directory (null to use default inline code)"
  type        = string
  default     = null
}

# =============================================================================
# S3 Settings
# =============================================================================

variable "s3_bucket_name" {
  description = "S3 bucket name (null for auto-generated)"
  type        = string
  default     = null
}

variable "s3_versioning_enabled" {
  description = "Enable S3 versioning"
  type        = bool
  default     = false
}

variable "s3_lifecycle_days" {
  description = "Days to retain objects (0 for no lifecycle rule)"
  type        = number
  default     = 90
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
