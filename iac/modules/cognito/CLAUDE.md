# CLAUDE.md - Amazon Cognito

Amazon Cognito User Pool を作成するTerraformモジュール。OAuth 2.0 認証フローをサポート。

## Overview

このモジュールは以下のリソースを作成します:
- Cognito User Pool
- User Pool Client
- User Pool Domain (Hosted UI用)
- Resource Server (カスタムスコープ用)

## Key Resources

- `aws_cognito_user_pool.this` - User Pool本体
- `aws_cognito_user_pool_client.this` - User Poolクライアント
- `aws_cognito_user_pool_domain.this` - User Poolドメイン
- `aws_cognito_resource_server.this` - リソースサーバー (for_each)

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| user_pool_name | string | Cognito User Pool名 |
| username_attributes | list(string) | ユーザー名として使用する属性 (default: ["email"]) |
| auto_verified_attributes | list(string) | 自動検証する属性 (default: ["email"]) |
| mfa_configuration | string | MFA設定 (OFF, ON, OPTIONAL) |
| allow_admin_create_user_only | bool | 管理者のみがユーザー作成可能か |
| password_policy | object | パスワードポリシー設定 |
| email_configuration | object | メール設定 (SES使用時) |
| schema_attributes | list(object) | カスタムユーザー属性スキーマ |
| lambda_config | object | Lambdaトリガー設定 |
| create_user_pool_client | bool | User Poolクライアントを作成するか (default: true) |
| user_pool_client_name | string | クライアント名 (default: "app-client") |
| generate_client_secret | bool | クライアントシークレットを生成するか (default: true) |
| explicit_auth_flows | list(string) | 許可する認証フロー |
| allowed_oauth_flows | list(string) | 許可するOAuthフロー (default: ["code"]) |
| allowed_oauth_scopes | list(string) | 許可するOAuthスコープ (default: ["openid", "email", "profile"]) |
| callback_urls | list(string) | コールバックURL |
| logout_urls | list(string) | ログアウトURL |
| access_token_validity | number | アクセストークン有効期間 |
| id_token_validity | number | IDトークン有効期間 |
| refresh_token_validity | number | リフレッシュトークン有効期間 |
| create_user_pool_domain | bool | User Poolドメインを作成するか |
| user_pool_domain | string | ドメイン名 (Hosted UI用) |
| resource_servers | map(object) | リソースサーバー設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| user_pool_id | Cognito User Pool ID |
| user_pool_arn | Cognito User Pool ARN |
| user_pool_endpoint | Cognito User Pool エンドポイント |
| user_pool_name | Cognito User Pool 名 |
| user_pool_client_id | User Poolクライアント ID |
| user_pool_client_secret | User Poolクライアントシークレット (sensitive) |
| user_pool_domain | User Poolドメイン |
| cognito_domain_url | Cognito Hosted UI ドメイン URL |
| oauth_authorize_url | OAuth 認可エンドポイント URL |
| oauth_token_url | OAuth トークンエンドポイント URL |
| oauth_userinfo_url | OAuth ユーザー情報エンドポイント URL |
| oauth_logout_url | OAuth ログアウトエンドポイント URL |
| jwks_url | JWKS エンドポイント URL |
| resource_server_identifiers | リソースサーバー識別子マップ |

## Usage Example

```hcl
module "cognito" {
  source = "../../modules/cognito"

  user_pool_name = "${var.project_name}-${var.environment}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy = {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  mfa_configuration = "OPTIONAL"

  user_pool_client_name   = "web-app"
  generate_client_secret  = false  # SPAの場合はfalse
  explicit_auth_flows     = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]

  allowed_oauth_flows  = ["code"]
  allowed_oauth_scopes = ["openid", "email", "profile"]

  callback_urls = ["https://app.example.com/auth/callback"]
  logout_urls   = ["https://app.example.com/"]

  create_user_pool_domain = true
  user_pool_domain        = "${var.project_name}-${var.environment}"

  tags = var.tags
}
```

## Important Notes

- SPAの場合は `generate_client_secret = false` を設定
- Lambdaトリガーは認証フローのカスタマイズに使用 (pre_sign_up, post_confirmation等)
- Hosted UIは `user_pool_domain` で有効化
- カスタムドメインには `domain_certificate_arn` (us-east-1のACM証明書) が必要
- リソースサーバーはAPI用のカスタムスコープを定義
- `prevent_user_existence_errors = "ENABLED"` でユーザー列挙攻撃を防止
- JWKS URLでIDトークンの署名検証が可能
