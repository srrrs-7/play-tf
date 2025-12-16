# =============================================================================
# General Variables
# =============================================================================

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名（リソース名のプレフィックスに使用）"
  type        = string
  default     = "ec2-vpc-endpoint"
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
  default     = "dev"
}

variable "stack_name" {
  description = "スタック名（リソースのグループ識別用）"
  type        = string
}

# =============================================================================
# VPC Variables
# =============================================================================

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "パブリックサブネットのCIDRブロック（NAT Instance用）"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "プライベートサブネットのCIDRブロック（EC2用）"
  type        = string
  default     = "10.0.1.0/24"
}

# =============================================================================
# NAT Instance Variables
# =============================================================================

variable "nat_instance_type" {
  description = "NAT Instanceのインスタンスタイプ（t4g.nano推奨: ~$3/月）"
  type        = string
  default     = "t4g.nano"
}

variable "nat_instance_type_is_arm" {
  description = "NAT Instanceのインスタンスタイプがt4g/t3g等のARMかどうか"
  type        = bool
  default     = true
}

variable "create_nat_instance" {
  description = "NAT Instanceを作成するかどうか"
  type        = bool
  default     = true
}

# =============================================================================
# EC2 Variables
# =============================================================================

variable "ec2_instance_type" {
  description = "EC2インスタンスタイプ（t3.micro推奨: 無料枠対象）"
  type        = string
  default     = "t3.micro"
}

variable "ec2_root_volume_size" {
  description = "EC2のルートボリュームサイズ（GB）"
  type        = number
  default     = 8
}

variable "create_ec2_instance" {
  description = "EC2インスタンスを作成するかどうか"
  type        = bool
  default     = true
}

# =============================================================================
# VPC Endpoint Variables
# =============================================================================

variable "create_s3_endpoint" {
  description = "S3 Gateway VPC Endpointを作成するかどうか（無料）"
  type        = bool
  default     = true
}

variable "create_ssm_endpoints" {
  description = "SSM Interface VPC Endpointsを作成するかどうか（有料: ~$22/月）"
  type        = bool
  default     = true
}

# =============================================================================
# S3 Variables
# =============================================================================

variable "create_s3_bucket" {
  description = "S3バケットを作成するかどうか"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "S3バケット名（nullの場合は自動生成）"
  type        = string
  default     = null
}

variable "s3_enable_versioning" {
  description = "S3バケットのバージョニングを有効にするかどうか"
  type        = bool
  default     = true
}

# =============================================================================
# IAM Variables
# =============================================================================

variable "s3_full_access" {
  description = "S3へのフルアクセスを許可するかどうか（falseの場合は読み取り専用）"
  type        = bool
  default     = false
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "追加のタグ"
  type        = map(string)
  default     = {}
}
