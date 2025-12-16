# =============================================================================
# EC2 + NAT Instance + VPC Endpoint + S3 Architecture
# =============================================================================
# プライベートサブネット内のEC2インスタンスから:
# - NAT Instance経由でインターネットにアクセス（Git, npm等）
# - VPC Endpoint経由でS3にアクセス（無料）
# - Session Manager経由で接続（SSHなし、パブリックIPなし）
#
# コスト最小化設計:
# - S3 VPC Endpoint: Gatewayタイプ（無料）
# - SSM VPC Endpoints: Interfaceタイプ（最小限の3つ）
# - EC2: t3.micro（無料枠対象）
# - NAT Instance: t4g.nano（月額~$3、NAT Gatewayの代替）
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Stack       = var.stack_name
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

# 現在のリージョン情報
data "aws_region" "current" {}

# 利用可能なAZ（最初の1つを使用）
data "aws_availability_zones" "available" {
  state = "available"
}

# 最新のAmazon Linux 2023 AMI（x86_64）- EC2用
data "aws_ssm_parameter" "al2023_ami_x86" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# 最新のAmazon Linux 2023 AMI（ARM64）- NAT Instance用
data "aws_ssm_parameter" "al2023_ami_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # 使用するAZ（最初の1つ）
  az = data.aws_availability_zones.available.names[0]

  # AMI選択（NAT InstanceはARM/x86に応じて選択）
  nat_ami_id = var.nat_instance_type_is_arm ? data.aws_ssm_parameter.al2023_ami_arm64.value : data.aws_ssm_parameter.al2023_ami_x86.value
  ec2_ami_id = data.aws_ssm_parameter.al2023_ami_x86.value

  # リソース名プレフィックス
  name_prefix = "${var.project_name}-${var.environment}"

  # 共通タグ
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Stack       = var.stack_name
  }
}
