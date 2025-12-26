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
  default     = "sagemaker"
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
# S3 Settings
# =============================================================================

variable "create_s3_buckets" {
  description = "Whether to create S3 buckets for data and models"
  type        = bool
  default     = true
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "Allow destroying S3 buckets even if they contain objects"
  type        = bool
  default     = false
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which objects expire (0 to disable)"
  type        = number
  default     = 0
}

# =============================================================================
# IAM Settings
# =============================================================================

variable "create_iam_role" {
  description = "Whether to create IAM role for SageMaker"
  type        = bool
  default     = true
}

variable "iam_role_name" {
  description = "Name for the SageMaker execution role (if create_iam_role is true)"
  type        = string
  default     = "sagemaker-execution-role"
}

variable "existing_role_arn" {
  description = "ARN of existing IAM role to use (if create_iam_role is false)"
  type        = string
  default     = null
}

variable "additional_iam_policies" {
  description = "List of additional IAM policy ARNs to attach to the SageMaker role"
  type        = list(string)
  default     = []
}

# =============================================================================
# SageMaker Notebook Settings
# =============================================================================

variable "create_notebook" {
  description = "Whether to create a SageMaker notebook instance"
  type        = bool
  default     = false
}

variable "notebook_instance_type" {
  description = "Notebook instance type"
  type        = string
  default     = "ml.t3.medium"
}

variable "notebook_volume_size" {
  description = "Notebook EBS volume size in GB"
  type        = number
  default     = 20
}

variable "notebook_platform_identifier" {
  description = "Notebook platform identifier (notebook-al1-v1, notebook-al2-v1, notebook-al2-v2)"
  type        = string
  default     = "notebook-al2-v2"
}

variable "notebook_lifecycle_config_name" {
  description = "Name of lifecycle configuration to attach to notebook"
  type        = string
  default     = null
}

variable "notebook_direct_internet_access" {
  description = "Direct internet access for notebook (Enabled or Disabled)"
  type        = string
  default     = "Enabled"
}

# =============================================================================
# SageMaker Experiment Settings
# =============================================================================

variable "create_experiment" {
  description = "Whether to create a SageMaker experiment"
  type        = bool
  default     = true
}

variable "experiment_description" {
  description = "Description for the SageMaker experiment"
  type        = string
  default     = null
}

# =============================================================================
# SageMaker Domain Settings (for Studio)
# =============================================================================

variable "create_domain" {
  description = "Whether to create a SageMaker Studio domain"
  type        = bool
  default     = false
}

variable "domain_auth_mode" {
  description = "Authentication mode for SageMaker domain (IAM or SSO)"
  type        = string
  default     = "IAM"
}

variable "vpc_id" {
  description = "VPC ID for SageMaker domain (required if create_domain is true)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for SageMaker domain (required if create_domain is true)"
  type        = list(string)
  default     = []
}

# =============================================================================
# CloudWatch Settings
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "enable_cloudwatch_metrics" {
  description = "Enable CloudWatch metrics for SageMaker"
  type        = bool
  default     = true
}

# =============================================================================
# Training Job Default Settings
# =============================================================================

variable "default_training_instance_type" {
  description = "Default instance type for training jobs"
  type        = string
  default     = "ml.m5.large"
}

variable "default_training_instance_count" {
  description = "Default instance count for training jobs"
  type        = number
  default     = 1
}

variable "default_training_volume_size" {
  description = "Default volume size in GB for training jobs"
  type        = number
  default     = 50
}

variable "default_max_runtime_seconds" {
  description = "Default max runtime in seconds for training jobs"
  type        = number
  default     = 86400
}

# =============================================================================
# Processing Job Default Settings
# =============================================================================

variable "default_processing_instance_type" {
  description = "Default instance type for processing jobs"
  type        = string
  default     = "ml.m5.large"
}

variable "default_processing_instance_count" {
  description = "Default instance count for processing jobs"
  type        = number
  default     = 1
}

variable "default_processing_volume_size" {
  description = "Default volume size in GB for processing jobs"
  type        = number
  default     = 50
}

# =============================================================================
# Model Registry Settings
# =============================================================================

variable "create_model_package_group" {
  description = "Whether to create a model package group for model registry"
  type        = bool
  default     = false
}

variable "model_package_group_description" {
  description = "Description for the model package group"
  type        = string
  default     = null
}
