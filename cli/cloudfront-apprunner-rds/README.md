# CloudFront → App Runner → RDS CLI

CloudFront、AWS App Runner、RDSを使用したマネージドコンテナアーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [App Runner] → [RDS]
                                  ↓
                            [ECR Image]
                            [自動スケーリング]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-app` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-app` |
| `status <stack-name>` | 全コンポーネントの状態表示 | `./script.sh status my-app` |

### App Runner操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `apprunner-create <name> <image-uri>` | サービス作成 | `./script.sh apprunner-create my-app 123456789.dkr.ecr.../app:latest` |
| `apprunner-delete <service-arn>` | サービス削除 | `./script.sh apprunner-delete arn:aws:apprunner:...` |
| `apprunner-list` | サービス一覧 | `./script.sh apprunner-list` |
| `apprunner-update <service-arn>` | サービス更新 | `./script.sh apprunner-update arn:aws:apprunner:...` |
| `apprunner-pause <service-arn>` | サービス一時停止 | `./script.sh apprunner-pause arn:aws:apprunner:...` |
| `apprunner-resume <service-arn>` | サービス再開 | `./script.sh apprunner-resume arn:aws:apprunner:...` |
| `apprunner-logs <service-name>` | ログ取得 | `./script.sh apprunner-logs my-app` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <apprunner-url> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create abc123.ap-northeast-1.awsapprunner.com my-app` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234...` |
| `cf-invalidate <dist-id> <path>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/*"` |

### RDS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `rds-create <id> <user> <pass> <subnet-group> <sg>` | RDS作成 | `./script.sh rds-create my-db admin pass123 my-subnet sg-123...` |
| `rds-delete <id>` | RDS削除 | `./script.sh rds-delete my-db` |
| `rds-list` | RDS一覧 | `./script.sh rds-list` |
| `rds-status <id>` | ステータス確認 | `./script.sh rds-status my-db` |

### ECR操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `ecr-create <name>` | リポジトリ作成 | `./script.sh ecr-create my-app` |
| `ecr-login` | ECRログイン | `./script.sh ecr-login` |
| `ecr-push <repo> <image> <tag>` | イメージプッシュ | `./script.sh ecr-push my-app my-app:latest v1.0` |

### VPC Connector操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `vpc-connector-create <name> <subnets> <sg>` | VPCコネクタ作成 | `./script.sh vpc-connector-create my-conn subnet-a,subnet-b sg-123...` |
| `vpc-connector-delete <name>` | VPCコネクタ削除 | `./script.sh vpc-connector-delete my-conn` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-app

# イメージ更新（自動デプロイ）
./script.sh ecr-login
docker build -t my-app:v2 .
./script.sh ecr-push my-app my-app:v2 v2

# 手動デプロイトリガー
./script.sh apprunner-update arn:aws:apprunner:...

# サービス一時停止（コスト削減）
./script.sh apprunner-pause arn:aws:apprunner:...

# ログ確認
./script.sh apprunner-logs my-app

# 全リソース削除
./script.sh destroy my-app
```

## App Runnerの特徴

- コンテナの自動スケーリング
- ECRからの自動デプロイ
- HTTPSエンドポイントの自動プロビジョニング
- VPC Connectorを使用したプライベートリソースへのアクセス
