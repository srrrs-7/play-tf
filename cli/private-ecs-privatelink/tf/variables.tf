# =============================================================================
# General Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "private-ecs"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# =============================================================================
# VPC Variables
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "availability_zones" {
  description = "List of availability zones (leave empty for auto-selection)"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (application tier)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "endpoint_subnet_cidrs" {
  description = "CIDR blocks for VPC endpoint subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# =============================================================================
# VPC Endpoint Variables
# =============================================================================

variable "enable_ecr_endpoints" {
  description = "Enable ECR VPC endpoints (ecr.api and ecr.dkr)"
  type        = bool
  default     = true
}

variable "enable_logs_endpoint" {
  description = "Enable CloudWatch Logs VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_s3_endpoint" {
  description = "Enable S3 VPC endpoint (Gateway type)"
  type        = bool
  default     = true
}

variable "enable_ecs_endpoints" {
  description = "Enable ECS VPC endpoints"
  type        = bool
  default     = true
}

variable "enable_ssm_endpoints" {
  description = "Enable SSM VPC endpoints for ECS Exec"
  type        = bool
  default     = true
}

variable "enable_secrets_manager_endpoint" {
  description = "Enable Secrets Manager VPC endpoint"
  type        = bool
  default     = false
}

variable "enable_kms_endpoint" {
  description = "Enable KMS VPC endpoint"
  type        = bool
  default     = false
}

# =============================================================================
# ECS Variables
# =============================================================================

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image for ECS task"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 80
}

variable "container_cpu" {
  description = "CPU units for the container (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory for the container in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 4
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

# =============================================================================
# ALB Variables
# =============================================================================

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Enable access logs for ALB"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
  default     = ""
}

# =============================================================================
# PrivateLink Variables
# =============================================================================

variable "enable_privatelink_service" {
  description = "Enable VPC Endpoint Service for PrivateLink"
  type        = bool
  default     = true
}

variable "privatelink_allowed_principals" {
  description = "List of AWS principals allowed to access the PrivateLink service"
  type        = list(string)
  default     = []
}

variable "privatelink_acceptance_required" {
  description = "Require manual acceptance of PrivateLink connections"
  type        = bool
  default     = true
}

# =============================================================================
# Transit Gateway Variables
# =============================================================================

variable "enable_transit_gateway" {
  description = "Enable Transit Gateway for Direct Connect integration"
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Existing Transit Gateway ID to attach (leave empty to create new)"
  type        = string
  default     = ""
}

variable "transit_gateway_cidr_blocks" {
  description = "CIDR blocks reachable via Transit Gateway (on-premises networks)"
  type        = list(string)
  default     = ["192.168.0.0/16", "172.16.0.0/12"]
}

variable "transit_gateway_asn" {
  description = "BGP ASN for Transit Gateway (used only when creating new TGW)"
  type        = number
  default     = 64512
}

# =============================================================================
# Logging Variables
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# =============================================================================
# Tags
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
