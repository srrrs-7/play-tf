# CLAUDE.md - VPC

Amazon VPCネットワークインフラを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- VPC
- インターネットゲートウェイ
- パブリックサブネット
- プライベートサブネット
- データベースサブネット
- NAT Gateway（オプション）
- ルートテーブル
- DBサブネットグループ
- VPN Gateway（オプション）

## Key Resources

- `aws_vpc.main` - VPC
- `aws_internet_gateway.main` - インターネットゲートウェイ
- `aws_subnet.public` - パブリックサブネット
- `aws_subnet.private` - プライベートサブネット
- `aws_subnet.database` - データベースサブネット
- `aws_nat_gateway.main` - NAT Gateway
- `aws_eip.nat` - NAT Gateway用Elastic IP
- `aws_route_table.public` - パブリックルートテーブル
- `aws_route_table.private` - プライベートルートテーブル
- `aws_route_table.database` - データベースルートテーブル
- `aws_db_subnet_group.database` - DBサブネットグループ
- `aws_vpn_gateway.main` - VPN Gateway

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| vpc_name | string | VPC名（必須） |
| vpc_cidr | string | VPC CIDRブロック（デフォルト: 10.0.0.0/16） |
| azs | list(string) | 使用するAvailability Zones（必須） |
| public_subnet_cidrs | list(string) | パブリックサブネットCIDR |
| private_subnet_cidrs | list(string) | プライベートサブネットCIDR |
| database_subnet_cidrs | list(string) | データベースサブネットCIDR |
| enable_nat_gateway | bool | NAT Gateway作成（デフォルト: true） |
| single_nat_gateway | bool | 単一NAT Gateway使用（デフォルト: false） |
| enable_dns_hostnames | bool | DNSホスト名有効化（デフォルト: true） |
| enable_dns_support | bool | DNSサポート有効化（デフォルト: true） |
| enable_vpn_gateway | bool | VPN Gateway作成（デフォルト: false） |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| vpc_id | VPC ID |
| vpc_cidr | VPC CIDRブロック |
| public_subnet_ids | パブリックサブネットIDリスト |
| private_subnet_ids | プライベートサブネットIDリスト |
| database_subnet_ids | データベースサブネットIDリスト |
| database_subnet_group_name | DBサブネットグループ名 |
| nat_gateway_ids | NAT Gateway IDリスト |
| internet_gateway_id | Internet Gateway ID |
| public_route_table_id | パブリックルートテーブルID |
| private_route_table_ids | プライベートルートテーブルIDリスト |
| database_route_table_id | データベースルートテーブルID |

## Usage Example

### 基本的な3層VPC

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_name = "my-app-vpc"
  vpc_cidr = "10.0.0.0/16"

  azs = ["ap-northeast-1a", "ap-northeast-1c"]

  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false  # 各AZにNAT Gateway

  tags = {
    Environment = "production"
  }
}
```

### コスト最適化VPC（単一NAT Gateway）

```hcl
module "vpc_dev" {
  source = "../../modules/vpc"

  vpc_name = "dev-vpc"
  vpc_cidr = "10.1.0.0/16"

  azs = ["ap-northeast-1a", "ap-northeast-1c"]

  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true  # コスト削減

  tags = {
    Environment = "development"
  }
}
```

### NAT Gatewayなし（VPC Endpoints使用）

```hcl
module "vpc_serverless" {
  source = "../../modules/vpc"

  vpc_name = "serverless-vpc"
  vpc_cidr = "10.2.0.0/16"

  azs = ["ap-northeast-1a", "ap-northeast-1c"]

  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]

  enable_nat_gateway = false  # VPC Endpointsで代替

  tags = {
    Environment = "production"
  }
}

# VPC Endpoints（S3、DynamoDB、ECR等）を別途作成
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc_serverless.vpc_id
  service_name      = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc_serverless.private_route_table_ids
}
```

### 他モジュールとの連携

```hcl
# VPC
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

# RDS
module "rds" {
  source = "../../modules/rds"

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  # ...
}

# ECS
module "ecs" {
  source = "../../modules/ecs"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  # ...
}

# ALB
module "alb" {
  source = "../../modules/alb"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids
  # ...
}
```

## Important Notes

- `enable_dns_hostnames = true`と`enable_dns_support = true`はデフォルト有効
- パブリックサブネットには`map_public_ip_on_launch = true`が設定
- NAT Gatewayはパブリックサブネットに配置
- `single_nat_gateway = true`でコスト削減（開発環境向け）
- `single_nat_gateway = false`で高可用性（本番環境向け）
- データベースサブネットは自動的にDBサブネットグループに追加
- データベースサブネットはインターネットアクセスなし（セキュリティ）
- VPC Endpoints使用時は`enable_nat_gateway = false`でコスト削減可能
