# AWS Amplify Hosting CLI

AWS Amplifyを使用したフルスタックWebアプリホスティングを管理するCLIスクリプトです。

## アーキテクチャ

```
[Git Repository] → [Amplify] → [CloudFront] → [Client]
        ↓              ↓            ↓
   [Branch Push]   [Build/Deploy]  [CDN配信]
   [Webhook]       [Preview URL]   [カスタムドメイン]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <name> [repo-url]` | Amplifyアプリをデプロイ | `./script.sh deploy my-app https://github.com/user/repo` |
| `destroy <app-id>` | アプリを削除 | `./script.sh destroy d1234567890` |
| `status` | 全アプリの状態表示 | `./script.sh status` |

### Amplify App操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `app-create <name>` | アプリ作成 | `./script.sh app-create my-app` |
| `app-create-repo <name> <repo-url> <token>` | リポジトリ連携アプリ作成 | `./script.sh app-create-repo my-app https://github.com/user/repo ghp_xxxxx` |
| `app-delete <app-id>` | アプリ削除 | `./script.sh app-delete d1234567890` |
| `app-list` | アプリ一覧 | `./script.sh app-list` |
| `app-status <app-id>` | アプリ詳細 | `./script.sh app-status d1234567890` |

### Branch操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `branch-create <app-id> <branch-name>` | ブランチ作成 | `./script.sh branch-create d123 main` |
| `branch-delete <app-id> <branch-name>` | ブランチ削除 | `./script.sh branch-delete d123 dev` |
| `branch-list <app-id>` | ブランチ一覧 | `./script.sh branch-list d123` |

### Deployment操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy-start <app-id> <branch>` | デプロイ開始 | `./script.sh deploy-start d123 main` |
| `deploy-stop <app-id> <branch> <job-id>` | デプロイ停止 | `./script.sh deploy-stop d123 main j123` |
| `deploy-list <app-id> <branch>` | デプロイ履歴 | `./script.sh deploy-list d123 main` |
| `deploy-manual <app-id> <branch> <zip-file>` | 手動デプロイ | `./script.sh deploy-manual d123 main dist.zip` |

### Domain操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `domain-create <app-id> <domain>` | カスタムドメイン追加 | `./script.sh domain-create d123 example.com` |
| `domain-delete <app-id> <domain>` | ドメイン削除 | `./script.sh domain-delete d123 example.com` |
| `domain-list <app-id>` | ドメイン一覧 | `./script.sh domain-list d123` |

### Environment Variables操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `env-set <app-id> <key> <value>` | 環境変数設定 | `./script.sh env-set d123 API_URL https://api.example.com` |
| `env-delete <app-id> <key>` | 環境変数削除 | `./script.sh env-delete d123 API_URL` |
| `env-list <app-id>` | 環境変数一覧 | `./script.sh env-list d123` |

### Webhook操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `webhook-create <app-id> <branch>` | Webhook作成 | `./script.sh webhook-create d123 main` |
| `webhook-delete <webhook-id>` | Webhook削除 | `./script.sh webhook-delete w123` |
| `webhook-list <app-id>` | Webhook一覧 | `./script.sh webhook-list d123` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# GitHubリポジトリからアプリ作成
./script.sh deploy my-app https://github.com/user/my-react-app

# アプリ一覧
./script.sh app-list

# ブランチ作成・デプロイ
./script.sh branch-create d1234567890 develop
./script.sh deploy-start d1234567890 develop

# デプロイ状態確認
./script.sh deploy-list d1234567890 main

# カスタムドメイン設定
./script.sh domain-create d1234567890 www.example.com

# 環境変数設定
./script.sh env-set d1234567890 REACT_APP_API_URL https://api.example.com

# 手動デプロイ（CI/CDなしでZIPファイルをデプロイ）
cd my-app && npm run build && zip -r dist.zip build/
./script.sh deploy-manual d1234567890 main dist.zip

# アプリ削除
./script.sh destroy d1234567890
```

## amplify.yml (ビルド設定例)

```yaml
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
```

## サポートされるフレームワーク

| フレームワーク | baseDirectory |
|---------------|---------------|
| React (CRA) | `build` |
| Next.js | `.next` |
| Vue.js | `dist` |
| Angular | `dist/<project-name>` |
| Gatsby | `public` |
| Nuxt.js | `dist` |

## ブランチ戦略

| ブランチ | 環境 | URL例 |
|---------|------|-------|
| main | 本番 | `https://main.d1234567890.amplifyapp.com` |
| develop | 開発 | `https://develop.d1234567890.amplifyapp.com` |
| feature/* | プレビュー | `https://pr-123.d1234567890.amplifyapp.com` |

## カスタムドメイン設定

1. `domain-create`でドメイン追加
2. DNS設定情報を確認（`domain-list`）
3. DNSプロバイダでCNAMEレコード設定
4. SSL証明書の自動発行を待機

## 注意事項

- GitHubとの連携にはPersonal Access Tokenが必要です
- ブランチごとに異なるURLが生成されます
- 自動ビルドはリポジトリへのpushで起動します
- Amplify Hostingは転送量とビルド時間で課金されます
- プレビュー環境はPull Request作成時に自動生成できます
