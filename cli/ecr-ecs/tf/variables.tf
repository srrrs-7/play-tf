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
  default     = "ecr-ecs"
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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (for ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks (for ECS tasks)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
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

# =============================================================================
# ECS Settings
# =============================================================================

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 80
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

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Container image URI (if null, uses ECR repository with 'latest' tag)"
  type        = string
  default     = null
}

variable "create_ecs_service" {
  description = "Whether to create ECS service (set to false if no image is pushed yet)"
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

# =============================================================================
# ALB Settings
# =============================================================================

variable "alb_internal" {
  description = "Whether ALB is internal"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "healthy_threshold" {
  description = "Number of consecutive health checks successes required"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive health check failures required"
  type        = number
  default     = 3
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "deregistration_delay" {
  description = "Target group deregistration delay in seconds"
  type        = number
  default     = 30
}

# =============================================================================
# Logging Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7
}

# =============================================================================
# CloudWatch Logs Insights / Metrics Settings
# =============================================================================

variable "enable_error_metric_filter" {
  description = "Enable CloudWatch metric filter for error count"
  type        = bool
  default     = true
}

variable "enable_request_metric_filter" {
  description = "Enable CloudWatch metric filter for request count"
  type        = bool
  default     = false
}

variable "enable_error_alarm" {
  description = "Enable CloudWatch alarm for error count"
  type        = bool
  default     = false
}

variable "error_alarm_threshold" {
  description = "Error count threshold for alarm"
  type        = number
  default     = 10
}
