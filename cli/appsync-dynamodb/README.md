# AppSync → DynamoDB CLI

AWS AppSyncとDynamoDBを使用したGraphQL API構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [AppSync GraphQL] → [DynamoDB]
                       ↓
                 [リゾルバー]
                 [リアルタイムサブスクリプション]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-graphql` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-graphql` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### AppSync操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `appsync-create <name>` | GraphQL API作成 | `./script.sh appsync-create my-api` |
| `appsync-delete <api-id>` | API削除 | `./script.sh appsync-delete abc123...` |
| `appsync-list` | API一覧 | `./script.sh appsync-list` |
| `appsync-get-url <api-id>` | GraphQL エンドポイント取得 | `./script.sh appsync-get-url abc123...` |
| `schema-update <api-id> <schema-file>` | スキーマ更新 | `./script.sh schema-update abc123... schema.graphql` |
| `datasource-create <api-id> <name> <table-name>` | データソース作成 | `./script.sh datasource-create abc123... UserDS users` |
| `resolver-create <api-id> <type> <field> <datasource>` | リゾルバー作成 | `./script.sh resolver-create abc123... Query getUser UserDS` |
| `apikey-create <api-id>` | APIキー作成 | `./script.sh apikey-create abc123...` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dynamodb-create <table> <pk> [sk]` | テーブル作成 | `./script.sh dynamodb-create users id` |
| `dynamodb-delete <table>` | テーブル削除 | `./script.sh dynamodb-delete users` |
| `dynamodb-list` | テーブル一覧 | `./script.sh dynamodb-list` |

## GraphQL操作

| 操作 | 説明 |
|-----|------|
| Query | データ取得 |
| Mutation | データ作成/更新/削除 |
| Subscription | リアルタイム更新 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-graphql

# GraphQLエンドポイント取得
./script.sh appsync-get-url abc123...
# https://xxx.appsync-api.ap-northeast-1.amazonaws.com/graphql

# APIキー取得
./script.sh apikey-create abc123...

# curlでGraphQLクエリ実行
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"query":"query { getUser(id: \"1\") { id name email } }"}' \
  https://xxx.appsync-api.../graphql

# 全リソース削除
./script.sh destroy my-graphql
```

## スキーマ例

```graphql
type User {
  id: ID!
  name: String!
  email: String!
  createdAt: AWSDateTime
}

type Query {
  getUser(id: ID!): User
  listUsers: [User]
}

type Mutation {
  createUser(name: String!, email: String!): User
  updateUser(id: ID!, name: String, email: String): User
  deleteUser(id: ID!): User
}

type Subscription {
  onCreateUser: User
    @aws_subscribe(mutations: ["createUser"])
}
```

## リゾルバーテンプレート例

### Query.getUser リクエストテンプレート
```vtl
{
  "version": "2017-02-28",
  "operation": "GetItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}
```

### Query.getUser レスポンステンプレート
```vtl
$util.toJson($ctx.result)
```
