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
  default     = "sns-lambda-fanout"
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

# =============================================================================
# Lambda Fan-out Settings
# =============================================================================

variable "lambda_functions" {
  description = "List of Lambda functions to create (fan-out targets)"
  type = list(object({
    name           = string
    description    = optional(string, "SNS fan-out Lambda function")
    filter_policy  = optional(string, null)
    memory_size    = optional(number, 256)
    timeout        = optional(number, 30)
    source_path    = optional(string, null)
    env_vars       = optional(map(string), {})
  }))
  default = [
    { name = "processor-1" },
    { name = "processor-2" },
    { name = "processor-3" }
  ]
}

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
