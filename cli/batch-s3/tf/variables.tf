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
  default     = "batch-s3"
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

variable "subnet_cidrs" {
  description = "Subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# =============================================================================
# Batch Settings
# =============================================================================

variable "compute_type" {
  description = "Batch compute environment type (FARGATE, FARGATE_SPOT, EC2, SPOT)"
  type        = string
  default     = "FARGATE"
}

variable "max_vcpus" {
  description = "Maximum vCPUs for compute environment"
  type        = number
  default     = 16
}

variable "job_vcpus" {
  description = "vCPUs for job definition"
  type        = number
  default     = 1
}

variable "job_memory" {
  description = "Memory for job definition in MB"
  type        = number
  default     = 2048
}

variable "container_image" {
  description = "Container image for job (default: amazon/aws-cli)"
  type        = string
  default     = "amazon/aws-cli"
}

variable "job_command" {
  description = "Default command for job"
  type        = list(string)
  default     = ["echo", "Hello from AWS Batch!"]
}

variable "job_timeout_seconds" {
  description = "Job timeout in seconds"
  type        = number
  default     = 3600
}

variable "job_retry_attempts" {
  description = "Number of retry attempts"
  type        = number
  default     = 1
}

# =============================================================================
# S3 Settings
# =============================================================================

variable "create_s3_buckets" {
  description = "Create S3 buckets for input/output"
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "Allow bucket to be destroyed even with objects"
  type        = bool
  default     = false
}
