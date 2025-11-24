# AWS VPC Module

AWS VPCネットワーク環境を作成するためのTerraformモジュールです。

## 機能

- VPCの作成
- パブリックサブネットとプライベートサブネットの作成
- インターネットゲートウェイの作成
- NAT Gatewayの作成（シングル/マルチAZ選択可）
- ルートテーブルの設定
- データベースサブネットの作成（オプション）
- VPN Gatewayの作成（オプション）

## 使用方法

```hcl
module "vpc" {
  source = "../modules/vpc"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
  
  azs             = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | VPC名 | `string` | n/a | yes |
| cidr | VPCのCIDRブロック | `string` | n/a | yes |
| azs | アベイラビリティゾーンのリスト | `list(string)` | n/a | yes |
| public_subnets | パブリックサブネットのCIDRリスト | `list(string)` | `[]` | no |
| private_subnets | プライベートサブネットのCIDRリスト | `list(string)` | `[]` | no |
| database_subnets | データベースサブネットのCIDRリスト | `list(string)` | `[]` | no |
| enable_nat_gateway | NAT Gatewayを作成するか | `bool` | `true` | no |
| single_nat_gateway | 単一のNAT Gatewayを使用するか | `bool` | `false` | no |
| enable_dns_hostnames | DNSホスト名を有効にするか | `bool` | `true` | no |
| enable_dns_support | DNSサポートを有効にするか | `bool` | `true` | no |
| enable_vpn_gateway | VPN Gatewayを作成するか | `bool` | `false` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | VPC ID |
| vpc_cidr_block | VPC CIDRブロック |
| public_subnet_ids | パブリックサブネットIDのリスト |
| private_subnet_ids | プライベートサブネットIDのリスト |
| database_subnet_ids | データベースサブネットIDのリスト |
| nat_public_ips | NAT GatewayのパブリックIPリスト |
