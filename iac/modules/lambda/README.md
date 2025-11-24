# AWS Lambda Module

AWS Lambda関数を作成するためのTerraformモジュールです。

## 機能

- Lambda関数の作成
- 実行ロール（IAM Role）の自動作成
- CloudWatch Logsグループの作成
- ソースコードのZIP化（ディレクトリまたはファイル指定）
- VPC設定のサポート
- 環境変数の設定
- Lambda Layerのサポート
- アーキテクチャ指定（x86_64/arm64）

## 使用方法

```hcl
module "lambda" {
  source = "../modules/lambda"

  function_name = "my-function"
  description   = "My Lambda Function"
  runtime       = "python3.11"
  handler       = "index.handler"
  source_path   = "./src"

  environment_variables = {
    ENV = "production"
  }

  tags = {
    Environment = "production"
    Project     = "my-project"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| function_name | Lambda関数名 | `string` | n/a | yes |
| description | Lambda関数の説明 | `string` | `""` | no |
| runtime | ランタイム (e.g., python3.11, nodejs20.x) | `string` | n/a | yes |
| handler | ハンドラー (e.g., index.handler) | `string` | n/a | yes |
| source_path | ソースコードのパス | `string` | n/a | yes |
| timeout | タイムアウト秒数 | `number` | `30` | no |
| memory_size | メモリサイズ (MB) | `number` | `128` | no |
| environment_variables | 環境変数 | `map(string)` | `{}` | no |
| vpc_config | VPC設定 | `object` | `null` | no |
| layers | Lambda Layerのリスト | `list(string)` | `[]` | no |
| reserved_concurrent_executions | 予約済み同時実行数 | `number` | `-1` | no |
| architectures | アーキテクチャ | `list(string)` | `["x86_64"]` | no |
| create_log_group | CloudWatch Logs グループを作成するか | `bool` | `true` | no |
| log_retention_days | ログ保持期間（日数） | `number` | `7` | no |
| policy_statements | 追加のIAMポリシーステートメント | `list(object)` | `[]` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| function_name | Lambda関数名 |
| function_arn | Lambda関数のARN |
| invoke_arn | Invoke ARN |
| qualified_arn | バージョン付きARN |
| version | 最新バージョン |
| role_arn | 実行ロールのARN |
| role_name | 実行ロール名 |
| log_group_name | CloudWatch Logsグループ名 |
