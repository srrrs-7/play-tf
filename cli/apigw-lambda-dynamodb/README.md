# API Gateway → Lambda → DynamoDB CLI

API Gateway、Lambda、DynamoDBを使用したサーバーレスREST API構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [API Gateway] → [Lambda] → [DynamoDB]
                      ↓
                 [REST API]
                 [CORS対応]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-api` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-api` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `api-create <name>` | REST API作成 | `./script.sh api-create my-api` |
| `api-delete <api-id>` | API削除 | `./script.sh api-delete abc123...` |
| `api-list` | API一覧 | `./script.sh api-list` |
| `api-deploy <api-id> <stage>` | APIデプロイ | `./script.sh api-deploy abc123... prod` |
| `api-get-url <api-id> <stage>` | API URL取得 | `./script.sh api-get-url abc123... prod` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create my-func func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update my-func func.zip` |
| `lambda-delete <name>` | Lambda削除 | `./script.sh lambda-delete my-func` |
| `lambda-invoke <name> <payload>` | 関数呼び出し | `./script.sh lambda-invoke my-func '{"key":"value"}'` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs my-func 30` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dynamodb-create <table> <pk> [sk]` | テーブル作成 | `./script.sh dynamodb-create users id` |
| `dynamodb-delete <table>` | テーブル削除 | `./script.sh dynamodb-delete users` |
| `dynamodb-list` | テーブル一覧 | `./script.sh dynamodb-list` |
| `dynamodb-put <table> <item>` | アイテム追加 | `./script.sh dynamodb-put users '{"id":"1","name":"John"}'` |
| `dynamodb-get <table> <key>` | アイテム取得 | `./script.sh dynamodb-get users '{"id":"1"}'` |
| `dynamodb-query <table> <key-condition>` | クエリ | `./script.sh dynamodb-query users "id = :id"` |
| `dynamodb-scan <table>` | 全スキャン | `./script.sh dynamodb-scan users` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-api

# APIエンドポイントURL取得
./script.sh api-get-url abc123... prod
# https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod

# curlでテスト
curl https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod/users
curl -X POST https://abc123.execute-api.../prod/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John","email":"john@example.com"}'

# ログ確認
./script.sh lambda-logs my-api-handler 60

# 全リソース削除
./script.sh destroy my-api
```
