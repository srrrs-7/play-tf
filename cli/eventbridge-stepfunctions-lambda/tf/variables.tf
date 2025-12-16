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
  default     = "eb-sfn-lambda"
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
# EventBridge Settings
# =============================================================================

variable "event_source" {
  description = "Event source for EventBridge rule"
  type        = string
  default     = "order.service"
}

variable "event_detail_type" {
  description = "Event detail type for EventBridge rule"
  type        = string
  default     = "OrderCreated"
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
  default     = 30
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
# Step Functions Settings
# =============================================================================

variable "sfn_type" {
  description = "Step Functions type (STANDARD or EXPRESS)"
  type        = string
  default     = "STANDARD"
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
