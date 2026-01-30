# CLAUDE.md - AWS App Runner

AWS App Runner サービスを作成するTerraformモジュール。ECRイメージまたはソースコードからコンテナアプリケーションを自動デプロイ。

## Overview

このモジュールは以下のリソースを作成します:
- App Runner Service
- Auto Scaling Configuration
- VPC Connector (VPCリソースへのアクセス用)
- ECR Access Role (ECRプル用)
- Instance Role (アプリケーション実行用)
- GitHub Connection (コードリポジトリ連携)
- Observability Configuration (X-Ray)
- Custom Domain Association

## Key Resources

- `aws_apprunner_service.main` - App Runnerサービス本体
- `aws_apprunner_auto_scaling_configuration_version.main` - オートスケーリング設定
- `aws_apprunner_vpc_connector.main` - VPCコネクタ
- `aws_iam_role.ecr_access` - ECRアクセス用IAMロール
- `aws_iam_role.instance` - インスタンス実行用IAMロール
- `aws_apprunner_connection.github` - GitHub接続
- `aws_apprunner_custom_domain_association.main` - カスタムドメイン

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| service_name | string | App Runnerサービス名 |
| source_type | string | ソースタイプ (ecr, code) |
| auto_deployments_enabled | bool | 自動デプロイを有効にするか |
| image_repository | object | ECRイメージリポジトリ設定 |
| code_repository | object | コードリポジトリ設定 |
| authentication_configuration | object | 認証設定 |
| cpu | string | CPU設定 (256, 512, 1024, 2048, 4096) |
| memory | string | メモリ設定 (512-12288) |
| create_instance_role | bool | インスタンスIAMロールを作成するか |
| instance_policy_statements | list(any) | インスタンスロールに追加するポリシー |
| health_check_configuration | object | ヘルスチェック設定 |
| network_configuration | object | ネットワーク設定 |
| create_vpc_connector | bool | VPCコネクタを作成するか |
| vpc_connector_subnets | list(string) | VPCコネクタ用サブネット |
| auto_scaling_max_concurrency | number | 最大同時リクエスト数 (default: 100) |
| auto_scaling_max_size | number | 最大インスタンス数 (default: 25) |
| auto_scaling_min_size | number | 最小インスタンス数 (default: 1) |
| kms_key_arn | string | 暗号化用KMSキーARN |
| custom_domains | map(object) | カスタムドメイン設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| service_id | App RunnerサービスID |
| service_arn | App RunnerサービスARN |
| service_url | App RunnerサービスURL |
| service_status | App Runnerサービスステータス |
| auto_scaling_configuration_arn | オートスケーリング設定ARN |
| vpc_connector_arn | VPCコネクタARN |
| ecr_access_role_arn | ECRアクセスロールARN |
| instance_role_arn | インスタンスロールARN |
| github_connection_arn | GitHub接続ARN |
| custom_domain_associations | カスタムドメイン情報 |

## Usage Example

```hcl
module "apprunner" {
  source = "../../modules/apprunner"

  service_name = "${var.project_name}-${var.environment}-service"
  source_type  = "ecr"

  image_repository = {
    image_identifier      = "${aws_ecr_repository.app.repository_url}:latest"
    image_repository_type = "ECR"
    image_configuration = {
      port = "8080"
      runtime_environment_variables = {
        NODE_ENV = "production"
      }
    }
  }

  cpu    = "1024"
  memory = "2048"

  health_check_configuration = {
    protocol = "HTTP"
    path     = "/health"
  }

  auto_scaling_min_size        = 1
  auto_scaling_max_size        = 10
  auto_scaling_max_concurrency = 100

  tags = var.tags
}
```

## Important Notes

- ECRソースの場合は `create_ecr_access_role = true` でプルアクセスを自動設定
- VPC内のリソース (RDS等) にアクセスする場合はVPCコネクタが必要
- GitHub連携はAWS ConsoleでのOAuth認証が必要な場合あり
- カスタムドメインはDNS検証が必要
- X-Ray統合は `create_observability_configuration = true` で有効化
- インスタンスロールにDynamoDBやS3へのアクセス権限を追加可能
