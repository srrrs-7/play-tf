# API Gateway → Lambda → RDS Proxy → RDS CLI

API Gateway、Lambda、RDS Proxy、RDSを使用したサーバーレスRDBMS接続アーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [API Gateway] → [Lambda] → [RDS Proxy] → [RDS]
                                                 ↓
                                          [接続プーリング]
                                          [フェイルオーバー]
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
| `api-deploy <api-id> <stage>` | APIデプロイ | `./script.sh api-deploy abc123... prod` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create my-func func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update my-func func.zip` |
| `lambda-set-vpc <name> <subnet-ids> <sg-ids>` | VPC設定 | `./script.sh lambda-set-vpc my-func subnet-a,subnet-b sg-123...` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs my-func 30` |

### RDS Proxy操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `proxy-create <name> <secret-arn> <subnet-ids> <sg-ids>` | プロキシ作成 | `./script.sh proxy-create my-proxy arn:aws:secretsmanager:... subnet-a,subnet-b sg-123...` |
| `proxy-delete <name>` | プロキシ削除 | `./script.sh proxy-delete my-proxy` |
| `proxy-list` | プロキシ一覧 | `./script.sh proxy-list` |
| `proxy-status <name>` | ステータス確認 | `./script.sh proxy-status my-proxy` |
| `proxy-add-target <proxy-name> <db-identifier>` | ターゲット追加 | `./script.sh proxy-add-target my-proxy my-db` |

### RDS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `rds-create <id> <user> <pass> <subnet-group> <sg>` | RDS作成 | `./script.sh rds-create my-db admin pass123 my-subnet sg-123...` |
| `rds-delete <id>` | RDS削除 | `./script.sh rds-delete my-db` |
| `rds-status <id>` | ステータス確認 | `./script.sh rds-status my-db` |
| `subnet-group-create <name> <subnet-ids>` | サブネットグループ作成 | `./script.sh subnet-group-create my-group subnet-a,subnet-b` |

### Secrets Manager操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `secret-create <name> <user> <pass> <host> <db>` | シークレット作成 | `./script.sh secret-create my-db-secret admin pass123 my-db.xxx.rds.amazonaws.com mydb` |
| `secret-delete <name>` | シークレット削除 | `./script.sh secret-delete my-db-secret` |

## RDS Proxyのメリット

| 機能 | 説明 |
|-----|------|
| 接続プーリング | Lambda同時実行時のDB接続数を削減 |
| 自動フェイルオーバー | RDSフェイルオーバー時の自動切り替え |
| IAM認証 | DB認証情報をSecrets Managerで管理 |
| TLS接続 | 暗号化された接続 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-api

# Lambda環境変数でプロキシエンドポイントを設定
./script.sh lambda-set-env my-func \
  DB_HOST=my-proxy.proxy-xxx.ap-northeast-1.rds.amazonaws.com \
  DB_NAME=mydb

# プロキシステータス確認
./script.sh proxy-status my-proxy

# 全リソース削除
./script.sh destroy my-api
```

## 注意事項

- RDS Proxyの作成には10-15分程度かかります
- LambdaはVPC内に配置する必要があります
- Secrets Managerでdb認証情報を管理することを推奨します
