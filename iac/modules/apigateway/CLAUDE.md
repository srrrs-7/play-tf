# CLAUDE.md - API Gateway REST API

AWS API Gateway REST API を作成するTerraformモジュール。Lambda統合とCORS設定をサポート。

## Overview

このモジュールは以下のリソースを作成します:
- API Gateway REST API
- プロキシリソース ({proxy+})
- ANY/OPTIONSメソッド
- Lambda統合
- ステージとデプロイメント
- CloudWatch Logsグループ

## Key Resources

- `aws_api_gateway_rest_api.this` - REST API本体
- `aws_api_gateway_resource.proxy` - プロキシリソース
- `aws_api_gateway_method.proxy` - ANYメソッド
- `aws_api_gateway_method.root` - ルートパスメソッド
- `aws_api_gateway_integration.proxy` - Lambda統合
- `aws_api_gateway_stage.this` - ステージ
- `aws_api_gateway_deployment.this` - デプロイメント
- `aws_cloudwatch_log_group.api_gateway` - ログ出力先
- `aws_lambda_permission.api_gateway` - Lambda実行権限

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| api_name | string | API Gateway の名前 |
| description | string | API Gateway の説明 |
| stage_name | string | ステージ名 (default: dev) |
| endpoint_types | list(string) | エンドポイントタイプ (EDGE, REGIONAL, PRIVATE) |
| lambda_invoke_arn | string | Lambda関数のInvoke ARN |
| lambda_function_name | string | Lambda関数名 |
| authorization_type | string | 認証タイプ (NONE, AWS_IAM, CUSTOM, COGNITO_USER_POOLS) |
| authorizer_id | string | Lambda Authorizer ID |
| xray_tracing_enabled | bool | X-Rayトレーシングを有効にするか |
| cache_cluster_size | string | キャッシュクラスタのサイズ |
| stage_variables | map(string) | ステージ変数 |
| create_log_group | bool | CloudWatch Logsグループを作成するか (default: true) |
| log_retention_days | number | ログ保持期間 (default: 7) |
| enable_cors | bool | CORSを有効にするか (default: false) |
| cors_allow_origin | string | CORS Allow-Origin ヘッダーの値 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | REST API ID |
| arn | REST API ARN |
| execution_arn | 実行ARN (Lambda権限用) |
| root_resource_id | ルートリソースID |
| stage_name | ステージ名 |
| stage_arn | ステージARN |
| invoke_url | API呼び出しURL |
| deployment_id | デプロイメントID |
| log_group_name | CloudWatch Logsグループ名 |
| log_group_arn | CloudWatch LogsグループARN |

## Usage Example

```hcl
module "api_gateway" {
  source = "../../modules/apigateway"

  api_name           = "${var.project_name}-${var.environment}-api"
  description        = "REST API for ${var.project_name}"
  stage_name         = var.environment
  endpoint_types     = ["REGIONAL"]

  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name

  enable_cors       = true
  cors_allow_origin = "'*'"

  log_retention_days = 30

  tags = var.tags
}
```

## Important Notes

- Lambda Proxy統合 (AWS_PROXY) を使用
- `{proxy+}` リソースで全パスをキャッチ
- ルートパス (/) も別途ハンドリング
- CORS設定時はOPTIONSメソッドを自動作成
- アクセスログはJSON形式で出力
- デプロイメントは関連リソース変更時に自動再作成
- Lambda権限は `/*/*` パターンで全メソッド・パスを許可
