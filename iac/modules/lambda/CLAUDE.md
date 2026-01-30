# CLAUDE.md - Lambda

AWS Lambda関数を構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- Lambda関数
- IAM実行ロールとポリシー
- CloudWatch Logsグループ
- ソースコードのZIPアーカイブ

## Key Resources

- `aws_lambda_function.main` - Lambda関数
- `aws_iam_role.lambda` - Lambda実行ロール
- `aws_iam_role_policy.lambda_custom` - カスタムIAMポリシー
- `aws_cloudwatch_log_group.lambda` - CloudWatch Logsグループ
- `data.archive_file.lambda` - ソースコードZIP

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| function_name | string | Lambda関数名（必須） |
| description | string | 関数の説明 |
| runtime | string | ランタイム（必須、例: nodejs20.x, python3.11） |
| handler | string | ハンドラー（必須、例: index.handler） |
| source_path | string | ソースコードパス（必須） |
| timeout | number | タイムアウト秒数（デフォルト: 30、最大: 900） |
| memory_size | number | メモリサイズMB（デフォルト: 128、最大: 10240） |
| environment_variables | map(string) | 環境変数 |
| vpc_config | object | VPC設定（subnet_ids, security_group_ids） |
| layers | list(string) | Lambda LayerのARNリスト |
| reserved_concurrent_executions | number | 予約済み同時実行数（-1で無制限） |
| architectures | list(string) | アーキテクチャ（x86_64/arm64） |
| create_log_group | bool | Logsグループ作成（デフォルト: true） |
| log_retention_days | number | ログ保持期間（デフォルト: 7） |
| policy_statements | list(object) | 追加IAMポリシーステートメント |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | Lambda関数ID |
| arn | Lambda関数ARN |
| function_name | Lambda関数名 |
| invoke_arn | API GatewayからのInvoke ARN |
| qualified_arn | バージョン付きARN |
| version | 最新バージョン |
| role_arn | 実行ロールのARN |
| role_name | 実行ロール名 |
| log_group_name | CloudWatch Logsグループ名 |

## Usage Example

### 基本的なLambda関数

```hcl
module "lambda" {
  source = "../../modules/lambda"

  function_name = "my-function"
  description   = "Sample Lambda function"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  source_path   = "./my-function/dist"
  timeout       = 30
  memory_size   = 256

  environment_variables = {
    TABLE_NAME = module.dynamodb.name
    LOG_LEVEL  = "INFO"
  }

  tags = {
    Environment = "production"
  }
}
```

### VPC内Lambda + カスタムポリシー

```hcl
module "lambda_vpc" {
  source = "../../modules/lambda"

  function_name = "vpc-function"
  runtime       = "python3.11"
  handler       = "main.handler"
  source_path   = "./vpc-function/dist"
  timeout       = 60
  memory_size   = 512
  architectures = ["arm64"]  # Graviton2

  vpc_config = {
    subnet_ids         = module.vpc.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  policy_statements = [
    {
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query"
      ]
      resources = [
        module.dynamodb.arn,
        "${module.dynamodb.arn}/index/*"
      ]
    },
    {
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject"
      ]
      resources = [
        "${module.s3.arn}/*"
      ]
    }
  ]

  log_retention_days = 30

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `source_path`はディレクトリを指定（自動的にZIP化される）
- VPC設定時は`AWSLambdaVPCAccessExecutionRole`ポリシーが自動付与
- `AWSLambdaBasicExecutionRole`（CloudWatch Logs権限）は常に付与
- `policy_statements`で追加のIAM権限を付与可能
- TypeScript Lambdaの場合は事前にビルド（`npm run build`）が必要
- `architectures = ["arm64"]`でGraviton2を使用（コスト効率向上）
- ログ保持期間は適切に設定してコストを管理
