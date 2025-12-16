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
  default     = "eb-sfn-ecs"
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
# VPC Settings
# =============================================================================

variable "use_default_vpc" {
  description = "Use default VPC instead of creating a new one"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "VPC CIDR block (if not using default VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# =============================================================================
# EventBridge Settings
# =============================================================================

variable "event_source" {
  description = "Event source for EventBridge rule"
  type        = string
  default     = "task.service"
}

variable "event_detail_type" {
  description = "Event detail type for EventBridge rule"
  type        = string
  default     = "TaskRequested"
}

# =============================================================================
# ECS Settings
# =============================================================================

variable "container_image" {
  description = "Container image for ECS task"
  type        = string
  default     = "amazon/amazon-ecs-sample"
}

variable "fargate_cpu" {
  description = "Fargate CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Fargate memory in MB"
  type        = number
  default     = 512
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
