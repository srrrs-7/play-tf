# ECR Operations CLI

Amazon ECR（Elastic Container Registry）の操作を行うCLIスクリプトです。

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### リポジトリ操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-repositories` | 全リポジトリ一覧表示 | `./script.sh list-repositories` |
| `create-repository <name>` | リポジトリ作成 | `./script.sh create-repository my-app` |
| `delete-repository <name>` | リポジトリ削除 | `./script.sh delete-repository my-app` |
| `describe-repository <name>` | リポジトリ詳細表示 | `./script.sh describe-repository my-app` |
| `get-repository-uri <name>` | リポジトリURI取得 | `./script.sh get-repository-uri my-app` |

### Docker認証

| コマンド | 説明 | 例 |
|---------|------|-----|
| `get-login` | Docker認証コマンド取得 | `./script.sh get-login` |
| `docker-login` | DockerをECRに認証 | `./script.sh docker-login` |

### イメージ操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-images <repo>` | イメージ一覧表示 | `./script.sh list-images my-app` |
| `describe-images <repo> [tag]` | イメージ詳細表示 | `./script.sh describe-images my-app latest` |
| `tag-image <repo> <src-tag> <new-tag>` | イメージにタグ付け | `./script.sh tag-image my-app v1.0 latest` |
| `delete-image <repo> <tag>` | イメージ削除 | `./script.sh delete-image my-app v1.0` |
| `push-image <repo> <local-image> [tag]` | イメージをプッシュ | `./script.sh push-image my-app my-app:latest v1.0` |
| `pull-image <repo> <tag>` | イメージをプル | `./script.sh pull-image my-app latest` |

### セキュリティスキャン

| コマンド | 説明 | 例 |
|---------|------|-----|
| `scan-image <repo> <tag>` | 脆弱性スキャン実行 | `./script.sh scan-image my-app latest` |
| `get-scan-findings <repo> <tag>` | スキャン結果取得 | `./script.sh get-scan-findings my-app latest` |

### ポリシー管理

| コマンド | 説明 | 例 |
|---------|------|-----|
| `set-lifecycle-policy <repo> <file>` | ライフサイクルポリシー設定 | `./script.sh set-lifecycle-policy my-app policy.json` |
| `get-lifecycle-policy <repo>` | ライフサイクルポリシー取得 | `./script.sh get-lifecycle-policy my-app` |
| `set-repository-policy <repo> <file>` | リポジトリポリシー設定 | `./script.sh set-repository-policy my-app policy.json` |
| `get-repository-policy <repo>` | リポジトリポリシー取得 | `./script.sh get-repository-policy my-app` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# Docker認証
./script.sh docker-login

# リポジトリ作成
./script.sh create-repository my-app

# ローカルイメージをプッシュ
docker build -t my-app:v1.0 .
./script.sh push-image my-app my-app:v1.0

# 脆弱性スキャン
./script.sh scan-image my-app v1.0
./script.sh get-scan-findings my-app v1.0
```
