# CloudFront → Elastic Beanstalk → RDS CLI

CloudFront、AWS Elastic Beanstalk、RDSを使用したPaaSアーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [Elastic Beanstalk] → [RDS]
                                    ↓
                            [Auto Scaling]
                            [Load Balancer]
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

### Elastic Beanstalk操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `eb-create-app <name>` | アプリケーション作成 | `./script.sh eb-create-app my-app` |
| `eb-delete-app <name>` | アプリケーション削除 | `./script.sh eb-delete-app my-app` |
| `eb-create-env <app> <env-name> <platform>` | 環境作成 | `./script.sh eb-create-env my-app my-env "64bit Amazon Linux 2 v3.5.0 running Node.js 18"` |
| `eb-delete-env <env-name>` | 環境削除 | `./script.sh eb-delete-env my-env` |
| `eb-list-apps` | アプリケーション一覧 | `./script.sh eb-list-apps` |
| `eb-list-envs <app>` | 環境一覧 | `./script.sh eb-list-envs my-app` |
| `eb-deploy <app> <env> <zip>` | アプリデプロイ | `./script.sh eb-deploy my-app my-env app.zip` |
| `eb-status <env>` | 環境ステータス | `./script.sh eb-status my-env` |
| `eb-health <env>` | ヘルスチェック | `./script.sh eb-health my-env` |
| `eb-logs <env>` | ログ取得 | `./script.sh eb-logs my-env` |
| `eb-scale <env> <min> <max>` | スケーリング設定 | `./script.sh eb-scale my-env 2 10` |
| `eb-set-env-vars <env> <key=value...>` | 環境変数設定 | `./script.sh eb-set-env-vars my-env DB_HOST=... DB_NAME=...` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <eb-url> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create my-env.elasticbeanstalk.com my-app` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234...` |
| `cf-invalidate <dist-id> <path>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/*"` |

### RDS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `rds-create <id> <user> <pass> <subnet-group> <sg>` | RDS作成 | `./script.sh rds-create my-db admin pass123 my-subnet sg-123...` |
| `rds-delete <id>` | RDS削除 | `./script.sh rds-delete my-db` |
| `rds-status <id>` | ステータス確認 | `./script.sh rds-status my-db` |

## サポートプラットフォーム

| 言語/フレームワーク | プラットフォーム例 |
|-------------------|-------------------|
| Node.js | `64bit Amazon Linux 2 v3.5.0 running Node.js 18` |
| Python | `64bit Amazon Linux 2 v3.4.0 running Python 3.9` |
| Java | `64bit Amazon Linux 2 v3.4.0 running Corretto 17` |
| Ruby | `64bit Amazon Linux 2 v3.5.0 running Ruby 3.1` |
| PHP | `64bit Amazon Linux 2 v3.5.0 running PHP 8.1` |
| Docker | `64bit Amazon Linux 2 v3.5.0 running Docker` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-app

# アプリケーションデプロイ
zip -r app.zip . -x "*.git*"
./script.sh eb-deploy my-app my-env app.zip

# 環境変数設定（RDS接続情報）
./script.sh eb-set-env-vars my-env \
  DB_HOST=my-db.xxx.ap-northeast-1.rds.amazonaws.com \
  DB_NAME=myapp \
  DB_USER=admin

# スケーリング設定
./script.sh eb-scale my-env 2 6

# ヘルスチェック
./script.sh eb-health my-env

# ログ確認
./script.sh eb-logs my-env

# 全リソース削除
./script.sh destroy my-app
```
