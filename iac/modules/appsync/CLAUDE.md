# CLAUDE.md - AWS AppSync GraphQL API

AWS AppSync GraphQL API を作成するTerraformモジュール。DynamoDB、Lambda、HTTPデータソースをサポート。

## Overview

このモジュールは以下のリソースを作成します:
- AppSync GraphQL API
- API Key (API_KEY認証の場合)
- Data Sources (DynamoDB, Lambda, HTTP, None)
- Resolvers (Unit/Pipeline)
- Functions (パイプラインリゾルバ用)

## Key Resources

- `aws_appsync_graphql_api.this` - GraphQL API本体
- `aws_appsync_api_key.this` - APIキー
- `aws_appsync_datasource.dynamodb` - DynamoDBデータソース
- `aws_appsync_datasource.lambda` - Lambdaデータソース
- `aws_appsync_datasource.http` - HTTPデータソース
- `aws_appsync_datasource.none` - Noneデータソース (ローカルリゾルバ)
- `aws_appsync_resolver.this` - リゾルバ
- `aws_appsync_function.this` - パイプライン関数

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | AppSync GraphQL API名 |
| authentication_type | string | 認証タイプ (API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, AWS_LAMBDA) |
| schema | string | GraphQLスキーマ定義 |
| additional_authentication_providers | list(object) | 追加の認証プロバイダー |
| lambda_authorizer_uri | string | Lambda Authorizer ARN |
| user_pool_id | string | Cognito User Pool ID |
| oidc_issuer | string | OIDC Issuer URL |
| create_api_key | bool | APIキーを作成するか |
| api_key_expires | string | APIキー有効期限 (RFC3339形式) |
| logging_enabled | bool | CloudWatchロギングを有効にするか |
| field_log_level | string | フィールドログレベル (ALL, ERROR, NONE) |
| xray_enabled | bool | X-Rayトレーシングを有効にするか |
| introspection_config | string | イントロスペクション設定 (ENABLED, DISABLED) |
| query_depth_limit | number | クエリ深度制限 (1-75) |
| visibility | string | API可視性 (GLOBAL, PRIVATE) |
| dynamodb_datasources | list(object) | DynamoDBデータソース設定 |
| lambda_datasources | list(object) | Lambdaデータソース設定 |
| http_datasources | list(object) | HTTPデータソース設定 |
| none_datasources | list(object) | Noneデータソース設定 |
| resolvers | list(object) | リゾルバ設定 |
| functions | list(object) | パイプライン関数設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | AppSync GraphQL API ID |
| arn | AppSync GraphQL API ARN |
| name | AppSync GraphQL API名 |
| uris | エンドポイントURIマップ |
| graphql_endpoint | GraphQLエンドポイントURL |
| realtime_endpoint | リアルタイムエンドポイントURL |
| api_key | APIキー (sensitive) |
| api_key_id | APIキーID |
| dynamodb_datasource_arns | DynamoDBデータソースARNマップ |
| lambda_datasource_arns | LambdaデータソースARNマップ |
| resolver_arns | リゾルバARNマップ |
| function_ids | パイプライン関数IDマップ |

## Usage Example

```hcl
module "appsync" {
  source = "../../modules/appsync"

  name                = "${var.project_name}-${var.environment}-api"
  authentication_type = "API_KEY"

  schema = <<-EOT
    type Query {
      getItem(id: ID!): Item
      listItems: [Item]
    }

    type Mutation {
      createItem(input: CreateItemInput!): Item
    }

    type Item {
      id: ID!
      name: String!
      createdAt: AWSDateTime!
    }

    input CreateItemInput {
      name: String!
    }
  EOT

  dynamodb_datasources = [
    {
      name             = "ItemsTable"
      table_name       = module.dynamodb.name
      service_role_arn = aws_iam_role.appsync.arn
    }
  ]

  resolvers = [
    {
      type              = "Query"
      field             = "getItem"
      data_source       = "ItemsTable"
      request_template  = file("${path.module}/resolvers/getItem-request.vtl")
      response_template = file("${path.module}/resolvers/getItem-response.vtl")
    }
  ]

  tags = var.tags
}
```

## Important Notes

- VTLテンプレートまたはJavaScriptランタイムでリゾルバを記述
- パイプラインリゾルバは複数の関数を順次実行
- Cognitoユーザープール認証はモバイル/Webアプリに最適
- リアルタイムサブスクリプションはWebSocket接続を使用
- APIキーは最大365日間有効
- `PRIVATE` 可視性はVPC内からのみアクセス可能
