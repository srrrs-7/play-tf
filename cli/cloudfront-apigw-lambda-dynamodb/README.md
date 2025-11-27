# CloudFront → API Gateway → Lambda → DynamoDB CLI

CloudFront、API Gateway、Lambda、DynamoDBを使用したフルサーバーレスアーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [API Gateway] → [Lambda] → [DynamoDB]
                  ↓
            [静的コンテンツ: S3]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-serverless-app` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-serverless-app` |
| `status <stack-name>` | 全コンポーネントの状態表示 | `./script.sh status my-serverless-app` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <api-url> <s3-bucket> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create https://abc123.execute-api... my-bucket my-app` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234...` |
| `cf-invalidate <dist-id> <path>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/api/*"` |

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `api-create <name>` | REST API作成 | `./script.sh api-create my-api` |
| `api-delete <api-id>` | API削除 | `./script.sh api-delete abc123...` |
| `api-list` | API一覧 | `./script.sh api-list` |
| `api-deploy <api-id> <stage>` | APIデプロイ | `./script.sh api-deploy abc123... prod` |
| `api-add-resource <api-id> <path>` | リソース追加 | `./script.sh api-add-resource abc123... /users` |
| `api-add-method <api-id> <resource-id> <method> <lambda-arn>` | メソッド追加 | `./script.sh api-add-method abc123... res123 GET arn:aws:lambda:...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create my-func func.zip index.handler nodejs18.x` |
| `lambda-delete <name>` | Lambda削除 | `./script.sh lambda-delete my-func` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update my-func func.zip` |
| `lambda-invoke <name> <payload>` | 関数呼び出し | `./script.sh lambda-invoke my-func '{"key":"value"}'` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs my-func 30` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dynamodb-create <table-name> <pk>` | テーブル作成 | `./script.sh dynamodb-create users id` |
| `dynamodb-delete <table-name>` | テーブル削除 | `./script.sh dynamodb-delete users` |
| `dynamodb-list` | テーブル一覧 | `./script.sh dynamodb-list` |
| `dynamodb-put <table> <item-json>` | アイテム追加 | `./script.sh dynamodb-put users '{"id":"1","name":"John"}'` |
| `dynamodb-get <table> <key-json>` | アイテム取得 | `./script.sh dynamodb-get users '{"id":"1"}'` |
| `dynamodb-scan <table>` | 全スキャン | `./script.sh dynamodb-scan users` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-serverless-app

# APIエンドポイント確認
./script.sh status my-serverless-app

# Lambda関数テスト
./script.sh lambda-invoke my-serverless-app-api '{"httpMethod":"GET","path":"/users"}'

# ログ確認
./script.sh lambda-logs my-serverless-app-api 60

# データ確認
./script.sh dynamodb-scan my-serverless-app-table

# 全リソース削除
./script.sh destroy my-serverless-app
```
