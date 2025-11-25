variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
}

# Presigned URL Lambda Variables
variable "presigned_url_default_expiration" {
  description = "Default expiration time for presigned URLs in seconds"
  type        = number
  default     = 3600
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

variable "allowed_origins" {
  description = "Allowed origins for CORS"
  type        = list(string)
  default     = ["http://localhost:3000"]
}
