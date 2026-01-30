# CloudFront + Cognito + Lambda@Edge + S3 認証アーキテクチャ

ブラウザで画像URLを直接開く → 未認証なら Cognito ログイン → 認証後に画像表示という UX を実現する Terraform + CLI スクリプト。

## アーキテクチャ

```
Browser
  │
  │ ① GET /images/a.jpg
  ▼
CloudFront (Distribution)
  │
  │ ② Viewer Request で Lambda@Edge が Cookie を検査
  │    - OK: オリジンへ
  │    - NG: Cognito Hosted UI へ 302
  ▼
S3 (private, OAC)
  │
  ▼
画像レスポンス

OAuth フロー:
Browser -> CloudFront -> (Edge で未認証判定) -> 302 Cognito /authorize
  -> Cognito login -> 302 https://xxx.cloudfront.net/auth/callback?code=...
  -> CloudFront -> Lambda@Edge (callback 処理)
     -> code を token に交換 -> Cookie セット -> 302 元URLへ
  -> CloudFront -> (認証OK) -> S3 -> 画像表示
```

## 前提条件

- AWS CLI 設定済み（`aws configure` または SSO）
- Terraform >= 1.0
- Bun または Node.js 18.x（Lambda ビルド用）
- jq（JSON 処理用）

## デプロイ方法

### 方法 1: CLI スクリプト（推奨）

```bash
cd iac/environments/cloudfront-cognito-s3
./script.sh deploy my-auth-app
```

これにより以下のリソースが作成されます：
- Cognito User Pool（Hosted UI 付き）
- S3 バケット（完全非公開、OAC でアクセス）
- Lambda@Edge 関数（3つ）
- CloudFront ディストリビューション

### 方法 2: Terraform

```bash
cd iac/environments/cloudfront-cognito-s3

# 設定ファイル作成
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集

# Lambda ビルド（初回）
./build-lambdas.sh

# デプロイ
terraform init
terraform plan
terraform apply

# 設定値取得後に Lambda を再ビルド
REGION=$(terraform output -json lambda_config_values | jq -r '.COGNITO_REGION')
POOL_ID=$(terraform output -json lambda_config_values | jq -r '.COGNITO_USER_POOL_ID')
CLIENT_ID=$(terraform output -json lambda_config_values | jq -r '.COGNITO_CLIENT_ID')
CLIENT_SECRET=$(terraform output -raw cognito_client_secret)
COGNITO_DOMAIN=$(terraform output -json lambda_config_values | jq -r '.COGNITO_DOMAIN')
CF_DOMAIN=$(terraform output -json lambda_config_values | jq -r '.CLOUDFRONT_DOMAIN')

./build-lambdas.sh "$REGION" "$POOL_ID" "$CLIENT_ID" "$CLIENT_SECRET" "$COGNITO_DOMAIN" "$CF_DOMAIN"
terraform apply
```

## クイックスタート（CLI）

### 1. デプロイ

```bash
./script.sh deploy my-auth-app
```

### 2. テストユーザー作成

```bash
./script.sh cognito-create-user <pool-id> your@email.com
```

### 3. コンテンツアップロード

```bash
./script.sh s3-upload <bucket-name> test.jpg
```

### 4. 動作確認

ブラウザで `https://<cloudfront-domain>/test.jpg` を開く：
1. Cognito ログイン画面にリダイレクト
2. テストユーザーでログイン（初期パスワード: `TempPass123!`）
3. 画像が表示される

### 5. 削除

```bash
./script.sh destroy my-auth-app
```

## CLI コマンドリファレンス

### フルスタック操作

| コマンド | 説明 |
|----------|------|
| `deploy <stack-name>` | 全リソースをデプロイ |
| `destroy <stack-name>` | 全リソースを削除 |
| `status` | 全コンポーネントの状態表示 |
| `test-auth <url>` | 認証フローのテスト |

### Cognito 操作

| コマンド | 説明 |
|----------|------|
| `cognito-create <name>` | User Pool 作成 |
| `cognito-delete <pool-id>` | User Pool 削除 |
| `cognito-list` | User Pool 一覧表示 |
| `cognito-create-user <pool-id> <email>` | テストユーザー作成 |
| `cognito-domain <pool-id> <prefix>` | Cognito ドメイン設定 |

### Lambda@Edge 操作

| コマンド | 説明 |
|----------|------|
| `edge-build` | 全 Lambda@Edge 関数をビルド |
| `edge-deploy <stack-name>` | Lambda@Edge 関数をデプロイ |
| `edge-update <stack-name>` | Lambda@Edge 関数を更新 |

### S3 操作

| コマンド | 説明 |
|----------|------|
| `s3-create <bucket-name>` | S3 バケット作成 |
| `s3-upload <bucket> <file>` | ファイルアップロード |
| `s3-sync <bucket> <dir>` | ディレクトリ同期 |

### CloudFront 操作

| コマンド | 説明 |
|----------|------|
| `cf-invalidate <dist-id>` | キャッシュ無効化 |

## Terraform 変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `project_name` | プロジェクト名 | - |
| `environment` | 環境名 | `dev` |
| `cognito_domain_prefix` | Cognito ドメインプレフィックス | - |
| `mfa_configuration` | MFA 設定 | `OFF` |
| `cloudfront_price_class` | 価格クラス | `PriceClass_200` |

詳細は `variables.tf` を参照。

## Terraform 出力

| 出力 | 説明 |
|------|------|
| `cloudfront_url` | CloudFront URL |
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_client_id` | Cognito Client ID |
| `content_bucket_name` | S3 バケット名 |
| `lambda_config_values` | Lambda 設定値（再ビルド用） |

詳細は `outputs.tf` を参照。

## ディレクトリ構造

```
iac/environments/cloudfront-cognito-s3/
├── main.tf                    # Terraform リソース定義
├── variables.tf               # 変数定義
├── outputs.tf                 # 出力定義
├── terraform.tfvars.example   # 設定例
├── script.sh                  # CLI スクリプト
├── build-lambdas.sh           # Lambda ビルド（Terraform用）
├── README.md                  # このドキュメント
├── CLAUDE.md                  # Claude Code 用ガイド
└── lambda/                    # Lambda@Edge ソースコード
    ├── build.sh               # 統一ビルドスクリプト
    ├── shared/                # 共通モジュール
    │   ├── index.ts           # 再エクスポート
    │   ├── constants.ts       # 定数定義
    │   ├── config.ts          # 設定値（ビルド時に注入）
    │   ├── types.ts           # 型定義
    │   ├── http.ts            # HTTP リクエストユーティリティ
    │   ├── jwt.ts             # JWT 検証
    │   ├── cookies.ts         # Cookie 操作
    │   ├── cognito.ts         # Cognito URL/State 操作、getFullUrl()
    │   ├── token.ts           # トークン交換/リフレッシュ
    │   ├── query.ts           # クエリ文字列パース
    │   └── response.ts        # CloudFront レスポンス生成、createLoginRedirect()
    ├── auth-check/            # 認証チェック関数
    ├── auth-callback/         # OAuth コールバック処理
    └── auth-refresh/          # トークンリフレッシュ
```

## Lambda@Edge 関数

### auth-check (viewer-request)

全パス（`/auth/*` 以外）で実行される認証チェック関数。

**処理フロー:**
1. `/auth/logout` → Cookie 削除して Cognito logout へリダイレクト
2. `/auth/*` → 他の Lambda に委譲
3. Cookie から `cognito_id_token` を取得
4. トークンなし → Cognito Hosted UI へリダイレクト
5. JWT を JWKS で検証
6. 検証失敗 → Cookie 削除して Cognito へリダイレクト
7. 有効期限が近い → `/auth/refresh` へリダイレクト
8. 検証成功 → リクエストをオリジンへ転送

### auth-callback (viewer-request @ /auth/callback)

OAuth コールバック処理。code → tokens 交換、Cookie セット。

### auth-refresh (viewer-request @ /auth/refresh)

トークンリフレッシュ。refresh_token で新しいトークン取得。

## 共通モジュール API

### 認証フロー関連

| 関数 | 説明 |
|------|------|
| `createLoginRedirect(uri, clearCookies?)` | Cognito ログインへのリダイレクト生成 |
| `getFullUrl(path)` | CloudFront 完全 URL を生成 |
| `generateState(uri)` | CSRF 対策用 State パラメータ生成 |
| `decodeState(state, storedState)` | State パラメータの検証とデコード |
| `getLoginUrl(state)` | Cognito 認可 URL を生成 |
| `getLogoutUrl()` | Cognito ログアウト URL を生成 |

### JWT 検証

| 関数 | 説明 |
|------|------|
| `verifyToken(token, region, poolId, clientId)` | JWT 署名を JWKS で検証 |
| `isTokenExpiringSoon(payload, threshold)` | トークンが期限切れ間近か判定 |

### Cookie 操作

| 関数 | 説明 |
|------|------|
| `parseCookies(headers)` | Cookie ヘッダーをパース |
| `generateTokenCookies(idToken, accessToken, expiresIn, refreshToken?)` | トークン Cookie 生成 |
| `getClearCookies()` | 全 Cookie クリア用の Set-Cookie 生成 |
| `getStateCookie(state)` | State Cookie 生成 |
| `getClearStateCookie()` | State Cookie クリア |

### レスポンス生成

| 関数 | 説明 |
|------|------|
| `createRedirectResponse(location, cookies?)` | 302 リダイレクトレスポンス生成 |
| `createErrorResponse(message)` | 400 エラーレスポンス生成（HTML） |
| `createLoginRedirect(uri, clearCookies?)` | Cognito ログインへのリダイレクト |

### トークン操作

| 関数 | 説明 |
|------|------|
| `exchangeCodeForTokens(code, domain, clientId, secret, redirectUri)` | 認可コードをトークンに交換 |
| `refreshTokens(refreshToken, domain, clientId, secret)` | リフレッシュトークンで更新 |

## セキュリティ

### JWT 検証

- Cognito JWKS エンドポイントから公開鍵を取得
- JWKS は 1 時間キャッシュ
- 検証項目：署名（RS256）、issuer、audience、expiration、token_use

### Cookie 設定

| Cookie | 属性 | Max-Age |
|--------|------|---------|
| `cognito_id_token` | HttpOnly; Secure; SameSite=Lax | 3600秒 |
| `cognito_access_token` | HttpOnly; Secure; SameSite=Lax | 3600秒 |
| `cognito_refresh_token` | HttpOnly; Secure; SameSite=Strict | 30日 |
| `cognito_state` | HttpOnly; Secure; SameSite=Lax | 300秒 |

### CSRF 対策

- State パラメータに元 URL + nonce + timestamp を含む
- State を Cookie に保存して callback 時に検証

## Lambda ビルド

### CLI 経由

```bash
./script.sh edge-build
```

### 直接実行

```bash
cd lambda && ./build.sh
```

### 個別ビルド

```bash
cd lambda && ./build.sh auth-check
```

## トラブルシューティング

### ログインがリダイレクトループする

1. Cognito callback URL を確認
2. CloudFront ドメインと一致しているか確認
3. Lambda ログでエラーを確認

### トークン検証エラー

```bash
aws logs tail "/aws/lambda/us-east-1.<stack-name>-auth-check" \
  --follow --region us-east-1
```

### Lambda@Edge が削除できない

レプリカ削除には最大 1 時間かかります。

### TypeScript エラー: Cannot find module './shared'

IDE で発生する場合、TypeScript サーバーを再起動：
- VSCode: `Cmd/Ctrl+Shift+P` → "TypeScript: Restart TS Server"

ビルド時に発生する場合：
```bash
rm -rf lambda/*/dist lambda/*/node_modules lambda/*/shared
cd lambda && ./build.sh
```

## 制限事項

- Lambda@Edge は **us-east-1** にデプロイ
- Lambda@Edge の最大実行時間は **5 秒**（viewer-request）
- CloudFront デプロイには **数分〜15分**
- Lambda@Edge 削除には **最大1時間**

## 参考リンク

- [Amazon Cognito Hosted UI](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-app-integration.html)
- [Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-at-the-edge.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
