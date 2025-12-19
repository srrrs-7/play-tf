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
  default     = "lambda-ecr"
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
# ECR Settings
# =============================================================================

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "ecr_force_delete" {
  description = "Force delete ECR repository even if it contains images"
  type        = bool
  default     = false
}

variable "ecr_lifecycle_policy_count" {
  description = "Number of images to keep in ECR (0 to disable lifecycle policy)"
  type        = number
  default     = 10
}

# =============================================================================
# Lambda Settings
# =============================================================================

variable "lambda_memory_size" {
  description = "Lambda memory size in MB (128-10240)"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds (1-900)"
  type        = number
  default     = 30
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions (-1 for no limit)"
  type        = number
  default     = -1
}

variable "lambda_architecture" {
  description = "Lambda instruction set architecture (x86_64 or arm64)"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Architecture must be x86_64 or arm64."
  }
}

variable "lambda_environment_variables" {
  description = "Environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

variable "container_image_uri" {
  description = "Container image URI (if null, uses ECR repository with 'latest' tag)"
  type        = string
  default     = null
}

variable "container_image_tag" {
  description = "Container image tag to use when container_image_uri is null"
  type        = string
  default     = "latest"
}

variable "create_lambda_function" {
  description = "Whether to create Lambda function (set to false if no image is pushed yet)"
  type        = bool
  default     = false
}

# =============================================================================
# VPC Settings (Optional)
# =============================================================================

variable "enable_vpc" {
  description = "Enable VPC configuration for Lambda"
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "List of subnet IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

# =============================================================================
# API Gateway Settings (Optional)
# =============================================================================

variable "create_api_gateway" {
  description = "Create API Gateway to invoke Lambda via HTTP"
  type        = bool
  default     = false
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "api"
}

# =============================================================================
# CloudWatch Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = false
}

# =============================================================================
# CloudWatch Logs Insights Settings
# =============================================================================

variable "enable_logs_insights_queries" {
  description = "Create CloudWatch Logs Insights saved queries"
  type        = bool
  default     = true
}
