# AppSync → Lambda → Aurora CLI

AWS AppSync、Lambda、Auroraを使用したGraphQL API構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [AppSync GraphQL] → [Lambda Resolver] → [Aurora]
                       ↓
                 [複雑なビジネスロジック]
                 [RDBMSクエリ]
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
| `schema-update <api-id> <schema-file>` | スキーマ更新 | `./script.sh schema-update abc123... schema.graphql` |
| `datasource-lambda <api-id> <name> <lambda-arn>` | Lambdaデータソース作成 | `./script.sh datasource-lambda abc123... ResolverDS arn:aws:lambda:...` |
| `resolver-create <api-id> <type> <field> <datasource>` | リゾルバー作成 | `./script.sh resolver-create abc123... Query getUsers ResolverDS` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create resolver func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update resolver func.zip` |
| `lambda-set-vpc <name> <subnets> <sgs>` | VPC設定 | `./script.sh lambda-set-vpc resolver subnet-a,subnet-b sg-123...` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs resolver 30` |

### Aurora操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `aurora-create <cluster-id> <user> <pass> <subnet-group> <sg>` | Auroraクラスター作成 | `./script.sh aurora-create my-db admin pass123 my-subnet sg-...` |
| `aurora-delete <cluster-id>` | Auroraクラスター削除 | `./script.sh aurora-delete my-db` |
| `aurora-status <cluster-id>` | ステータス確認 | `./script.sh aurora-status my-db` |
| `subnet-group-create <name> <subnet-ids>` | サブネットグループ作成 | `./script.sh subnet-group-create my-group subnet-a,subnet-b` |

### VPC操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `vpc-create <name> <cidr>` | VPC作成 | `./script.sh vpc-create my-vpc 10.0.0.0/16` |
| `sg-create <name> <vpc-id> <desc>` | セキュリティグループ作成 | `./script.sh sg-create my-sg vpc-123... "My SG"` |

## Lambdaリゾルバーのメリット

| メリット | 説明 |
|---------|------|
| 複雑なロジック | VTLより柔軟なビジネスロジック実装 |
| RDBMSアクセス | SQL実行、トランザクション処理 |
| 外部API連携 | 他サービスとの統合 |
| 認証・認可 | カスタム認証ロジック |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-graphql

# Lambda VPC設定（Aurora接続用）
./script.sh lambda-set-vpc resolver subnet-priv-a,subnet-priv-b sg-123...

# GraphQLクエリ実行
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"query":"query { getUsers { id name email } }"}' \
  https://xxx.appsync-api.../graphql

# 全リソース削除
./script.sh destroy my-graphql
```

## Lambdaリゾルバー実装例

```javascript
const mysql = require('mysql2/promise');

exports.handler = async (event) => {
  const { fieldName, arguments: args } = event;

  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME
  });

  try {
    switch (fieldName) {
      case 'getUsers':
        const [users] = await connection.execute('SELECT * FROM users');
        return users;

      case 'createUser':
        const { name, email } = args;
        const [result] = await connection.execute(
          'INSERT INTO users (name, email) VALUES (?, ?)',
          [name, email]
        );
        return { id: result.insertId, name, email };

      default:
        throw new Error(`Unknown field: ${fieldName}`);
    }
  } finally {
    await connection.end();
  }
};
```
