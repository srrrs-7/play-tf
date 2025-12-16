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
  default     = "eventbridge-lambda"
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

variable "event_bus_name" {
  description = "EventBridge event bus name (null to use default)"
  type        = string
  default     = null
}

variable "create_custom_event_bus" {
  description = "Whether to create a custom event bus"
  type        = bool
  default     = true
}

variable "event_pattern" {
  description = "Event pattern for the rule (JSON string)"
  type        = string
  default     = <<-EOF
    {
      "source": [{"prefix": ""}]
    }
  EOF
}

variable "rule_description" {
  description = "Description for the EventBridge rule"
  type        = string
  default     = "Rule to trigger Lambda on events"
}

# =============================================================================
# Lambda Settings
# =============================================================================

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_handler" {
  description = "Lambda handler"
  type        = string
  default     = "index.handler"
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

variable "lambda_environment_variables" {
  description = "Environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}
