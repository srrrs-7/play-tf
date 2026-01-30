# CLAUDE.md - Elastic Beanstalk

AWS Elastic Beanstalk PaaS環境を構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- Elastic Beanstalkアプリケーション
- Elastic Beanstalk環境（WebServer/Worker）
- アプリケーションバージョン（オプション）
- IAMインスタンスプロファイルとロール（オプション）
- サービスロール（オプション）

## Key Resources

- `aws_elastic_beanstalk_application.main` - Beanstalkアプリケーション
- `aws_elastic_beanstalk_environment.main` - Beanstalk環境
- `aws_elastic_beanstalk_application_version.main` - アプリケーションバージョン
- `aws_iam_instance_profile.main` - EC2インスタンスプロファイル
- `aws_iam_role.instance` - インスタンスロール
- `aws_iam_role.service` - サービスロール

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| application_name | string | アプリケーション名（必須） |
| environment_name | string | 環境名（必須） |
| solution_stack_name | string | ソリューションスタック名（必須） |
| tier | string | 環境ティア（WebServer/Worker、デフォルト: WebServer） |
| vpc_id | string | VPC ID |
| subnet_ids | list(string) | インスタンス用サブネットID |
| elb_subnet_ids | list(string) | ELB用サブネットID |
| instance_type | string | EC2インスタンスタイプ（デフォルト: t3.micro） |
| min_instances | number | 最小インスタンス数（デフォルト: 1） |
| max_instances | number | 最大インスタンス数（デフォルト: 4） |
| environment_type | string | 環境タイプ（LoadBalanced/SingleInstance） |
| load_balancer_type | string | LBタイプ（classic/application/network） |
| create_instance_profile | bool | インスタンスプロファイル作成（デフォルト: true） |
| create_service_role | bool | サービスロール作成（デフォルト: true） |
| enhanced_reporting_enabled | bool | 拡張ヘルスレポート（デフォルト: true） |
| cloudwatch_logs_enabled | bool | CloudWatch Logs有効化 |
| environment_variables | map(string) | 環境変数 |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| application_name | アプリケーション名 |
| application_arn | アプリケーションARN |
| environment_id | 環境ID |
| environment_name | 環境名 |
| environment_arn | 環境ARN |
| environment_cname | 環境CNAME |
| environment_endpoint_url | 環境エンドポイントURL |
| environment_load_balancers | ロードバランサーリスト |
| instance_profile_name | インスタンスプロファイル名 |
| instance_role_arn | インスタンスロールARN |
| service_role_arn | サービスロールARN |

## Usage Example

```hcl
module "elasticbeanstalk" {
  source = "../../modules/elasticbeanstalk"

  application_name    = "my-webapp"
  environment_name    = "my-webapp-prod"
  solution_stack_name = "64bit Amazon Linux 2023 v4.0.0 running Python 3.11"
  tier                = "WebServer"

  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  elb_subnet_ids = module.vpc.public_subnet_ids

  instance_type    = "t3.small"
  min_instances    = 2
  max_instances    = 10
  environment_type = "LoadBalanced"

  environment_variables = {
    APP_ENV = "production"
  }

  cloudwatch_logs_enabled = true

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `solution_stack_name`はAWSコンソールまたはCLIで利用可能なスタックを確認してください
- `create_instance_profile = true`の場合、WebTier/MulticontainerDockerポリシーが自動付与されます
- `tier = "Worker"`の場合、WorkerTierポリシーも追加されます
- `managed_updates_enabled`を有効にすると、プラットフォーム更新が自動実行されます
- `additional_settings`で任意のBeanstalk設定を追加できます
