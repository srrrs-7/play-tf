# CLAUDE.md - AWS Amplify

AWS Amplify Hosting を作成するTerraformモジュール。GitHubなどのリポジトリと連携してフルスタックWebアプリケーションをホスティング。

## Overview

このモジュールは以下のリソースを作成します:
- Amplify App (メインアプリケーション)
- Amplify Branch (ブランチ設定、複数対応)
- Amplify Domain Association (カスタムドメイン)
- Amplify Webhook (ビルドトリガー)
- Backend Environment (Amplify Studio用)

## Key Resources

- `aws_amplify_app.this` - Amplifyアプリケーション本体
- `aws_amplify_branch.this` - ブランチ設定 (for_each)
- `aws_amplify_domain_association.this` - ドメイン関連付け (for_each)
- `aws_amplify_webhook.this` - Webhook (for_each)
- `aws_amplify_backend_environment.this` - バックエンド環境 (for_each)

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | Amplifyアプリ名 |
| description | string | Amplifyアプリの説明 |
| repository | string | リポジトリURL |
| access_token | string | GitHub Personal Access Token (sensitive) |
| oauth_token | string | OAuthトークン (sensitive) |
| build_spec | string | ビルド設定 (YAML形式) |
| enable_auto_branch_creation | bool | 自動ブランチ作成を有効にするか |
| enable_branch_auto_build | bool | ブランチの自動ビルドを有効にするか |
| enable_branch_auto_deletion | bool | ブランチ削除時に自動切断するか |
| enable_basic_auth | bool | Basic認証を有効にするか |
| environment_variables | map(string) | 環境変数 |
| iam_service_role_arn | string | IAMサービスロールARN |
| platform | string | プラットフォーム (WEB, WEB_COMPUTE, WEB_DYNAMIC) |
| custom_rules | list(object) | カスタムリダイレクト/リライトルール |
| branches | list(object) | ブランチ設定リスト |
| domain_associations | list(object) | ドメイン関連付け設定 |
| webhooks | list(object) | Webhook設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | AmplifyアプリID |
| arn | AmplifyアプリARN |
| name | Amplifyアプリ名 |
| default_domain | デフォルトドメイン |
| production_branch | プロダクションブランチ |
| branch_names | ブランチ名リスト |
| branch_arns | ブランチARNマップ |
| branch_urls | ブランチURLマップ |
| domain_association_arns | ドメイン関連付けARNマップ |
| webhook_urls | WebhookURLマップ |

## Usage Example

```hcl
module "amplify" {
  source = "../../modules/amplify"

  name        = "${var.project_name}-${var.environment}-app"
  description = "Frontend application"
  repository  = "https://github.com/org/repo"
  access_token = var.github_access_token

  platform = "WEB"

  build_spec = <<-EOT
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
        baseDirectory: dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  branches = [
    {
      branch_name       = "main"
      stage             = "PRODUCTION"
      enable_auto_build = true
    },
    {
      branch_name       = "develop"
      stage             = "DEVELOPMENT"
      enable_auto_build = true
    }
  ]

  environment_variables = {
    VITE_API_URL = "https://api.example.com"
  }

  tags = var.tags
}
```

## Important Notes

- `access_token` または `oauth_token` はsensitive変数として扱われる
- ブランチURLは `https://{branch_name}.{default_domain}` 形式
- カスタムドメインは `domain_associations` で設定
- Basic認証はステージング環境での保護に有用
- `WEB_COMPUTE` プラットフォームはSSR対応
