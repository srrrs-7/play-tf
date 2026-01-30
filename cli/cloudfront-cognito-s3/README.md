# CloudFront + Cognito + Lambda@Edge + S3 認証アーキテクチャ

ブラウザで画像URLを直接開く → 未認証なら Cognito ログイン → 認証後に画像表示という UX を実現する CLI スクリプト。

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
- Bun または Node.js 18.x（Lambda ビルド用）
- jq（JSON 処理用）

## クイックスタート

### 1. デプロイ

```bash
cd cli/cloudfront-cognito-s3
./script.sh deploy my-auth-app
```

これにより以下のリソースが作成されます：
- Cognito User Pool（Hosted UI 付き）
- S3 バケット（完全非公開、OAC でアクセス）
- Lambda@Edge 関数（3つ）
- CloudFront ディストリビューション

### 2. テストユーザー作成

```bash
./script.sh cognito-create-user <pool-id> your@email.com
```

デプロイ完了時に表示される `pool-id` を使用してください。

### 3. コンテンツアップロード

```bash
# 単一ファイル
./script.sh s3-upload <bucket-name> test.jpg

# ディレクトリ同期
./script.sh s3-sync <bucket-name> ./my-content
```

### 4. 動作確認

ブラウザで `https://<cloudfront-domain>/test.jpg` を開く：

1. Cognito ログイン画面にリダイレクトされる
2. テストユーザーでログイン（初期パスワード: `TempPass123!`）
3. 画像が表示される

### 5. 認証フローテスト（自動）

```bash
./script.sh test-auth https://<cloudfront-domain>
```

### 6. 削除

```bash
./script.sh destroy my-auth-app
```

## コマンドリファレンス

### フルスタック操作

| コマンド | 説明 | 例 |
|----------|------|-----|
| `deploy <stack-name>` | 全リソースをデプロイ | `./script.sh deploy my-app` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-app` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |
| `test-auth <url>` | 認証フローのテスト | `./script.sh test-auth https://xxx.cloudfront.net` |

### Cognito 操作

| コマンド | 説明 | 例 |
|----------|------|-----|
| `cognito-create <name>` | User Pool 作成 | `./script.sh cognito-create my-pool` |
| `cognito-delete <pool-id>` | User Pool 削除 | `./script.sh cognito-delete ap-northeast-1_xxx` |
| `cognito-list` | User Pool 一覧表示 | `./script.sh cognito-list` |
| `cognito-create-user <pool-id> <email>` | テストユーザー作成 | `./script.sh cognito-create-user ap-northeast-1_xxx user@example.com` |
| `cognito-domain <pool-id> <prefix>` | Cognito ドメイン設定 | `./script.sh cognito-domain ap-northeast-1_xxx my-app-auth` |

### Lambda@Edge 操作

| コマンド | 説明 | 例 |
|----------|------|-----|
| `edge-build` | 全 Lambda@Edge 関数をビルド | `./script.sh edge-build` |
| `edge-deploy <stack-name>` | Lambda@Edge 関数をデプロイ | `./script.sh edge-deploy my-app` |
| `edge-update <stack-name>` | Lambda@Edge 関数を更新 | `./script.sh edge-update my-app` |

### S3 操作

| コマンド | 説明 | 例 |
|----------|------|-----|
| `s3-create <bucket-name>` | S3 バケット作成 | `./script.sh s3-create my-content-bucket` |
| `s3-upload <bucket> <file>` | ファイルアップロード | `./script.sh s3-upload my-bucket image.jpg` |
| `s3-sync <bucket> <dir>` | ディレクトリ同期 | `./script.sh s3-sync my-bucket ./content` |

### CloudFront 操作

| コマンド | 説明 | 例 |
|----------|------|-----|
| `cf-invalidate <dist-id>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234567890ABC` |

## Lambda@Edge 関数

### auth-check (viewer-request)

全パス（`/auth/*` 以外）で実行される認証チェック関数。

**処理フロー:**
1. `/auth/logout` → Cookie 削除して Cognito logout へリダイレクト
2. `/auth/*` → 他の Lambda に委譲（パススルー）
3. Cookie から `cognito_id_token` を取得
4. トークンなし → Cognito Hosted UI へリダイレクト
5. JWT を JWKS で検証（署名、issuer、audience、expiration）
6. 検証失敗 → Cookie 削除して Cognito へリダイレクト
7. 有効期限が近い（5分以内）→ `/auth/refresh` へリダイレクト
8. 検証成功 → リクエストをオリジンへ転送

### auth-callback (viewer-request @ /auth/callback)

OAuth コールバック処理関数。

**処理フロー:**
1. Authorization code を受信
2. State パラメータを検証（Cookie との一致、タイムスタンプ）
3. Cognito Token Endpoint で code → tokens 交換
4. HttpOnly/Secure Cookie をセット
5. State に保存されていた元 URL へリダイレクト

### auth-refresh (viewer-request @ /auth/refresh)

トークンリフレッシュ関数。

**処理フロー:**
1. `refresh_token` Cookie を取得
2. トークンなし → Cognito へリダイレクト
3. Cognito Token Endpoint で新しいトークン取得
4. Cookie 更新（id_token, access_token）
5. 元 URL へリダイレクト

## セキュリティ

### JWT 検証

- Cognito JWKS エンドポイントから公開鍵を取得
- JWKS は 1 時間キャッシュ（Lambda のメモリ内）
- 検証項目：署名（RS256）、issuer、audience、expiration、token_use

### Cookie 設定

| Cookie | 属性 | Max-Age | 用途 |
|--------|------|---------|------|
| `cognito_id_token` | HttpOnly; Secure; SameSite=Lax | 3600秒 | JWT ID トークン |
| `cognito_access_token` | HttpOnly; Secure; SameSite=Lax | 3600秒 | アクセストークン |
| `cognito_refresh_token` | HttpOnly; Secure; SameSite=Strict | 30日 | リフレッシュトークン |
| `cognito_state` | HttpOnly; Secure; SameSite=Lax | 300秒 | CSRF 対策用 |

### CSRF 対策

- State パラメータに元 URL + nonce + timestamp を含む（Base64URL エンコード）
- State を Cookie に保存して callback 時に検証
- タイムスタンプは 5 分以内のみ有効

## CloudFront ビヘイビア設定

| パス | Lambda@Edge | キャッシュ | 説明 |
|------|-------------|------------|------|
| `/auth/callback` | auth-callback | TTL=0 | OAuth コールバック |
| `/auth/refresh` | auth-refresh | TTL=0 | トークンリフレッシュ |
| `/auth/logout` | auth-check | TTL=0 | ログアウト処理 |
| `/*` (default) | auth-check | 設定可能 | 認証チェック |

## ディレクトリ構造

```
cli/cloudfront-cognito-s3/
├── script.sh                      # メイン CLI スクリプト
├── README.md                      # このドキュメント
├── CLAUDE.md                      # Claude Code 用ガイド
└── lambda/                        # Lambda@Edge ソースコード
    ├── build.sh                   # 統一ビルドスクリプト
    ├── shared/                    # 共通モジュール
    │   ├── index.ts               # 再エクスポート
    │   ├── constants.ts           # 定数定義
    │   ├── config.ts              # 設定値（ビルド時に注入）
    │   ├── types.ts               # 型定義
    │   ├── http.ts                # HTTP リクエストユーティリティ
    │   ├── jwt.ts                 # JWT 検証
    │   ├── cookies.ts             # Cookie 操作
    │   ├── cognito.ts             # Cognito URL/State 操作
    │   ├── token.ts               # トークン交換/リフレッシュ
    │   ├── query.ts               # クエリ文字列パース
    │   └── response.ts            # CloudFront レスポンス生成
    ├── auth-check/                # 認証チェック関数
    │   ├── index.ts               # ハンドラー
    │   ├── package.json
    │   ├── tsconfig.json
    │   └── build.sh
    ├── auth-callback/             # OAuth コールバック処理
    │   ├── index.ts               # ハンドラー
    │   ├── package.json
    │   ├── tsconfig.json
    │   └── build.sh
    └── auth-refresh/              # トークンリフレッシュ
        ├── index.ts               # ハンドラー
        ├── package.json
        ├── tsconfig.json
        └── build.sh
```

## Lambda ビルド

### 全関数ビルド

```bash
cd lambda
./build.sh
```

### 個別ビルド

```bash
cd lambda
./build.sh auth-check
./build.sh auth-callback
./build.sh auth-refresh
```

### ビルドプロセス

1. `shared/` ディレクトリを各関数にコピー
2. 依存関係インストール（Bun 優先、npm フォールバック）
3. TypeScript コンパイル
4. `function.zip` 作成
5. コピーした `shared/` をクリーンアップ

### 設定値の注入

ビルドスクリプトは以下のプレースホルダーを実際の値に置換します：

| プレースホルダー | 説明 |
|-----------------|------|
| `{{COGNITO_REGION}}` | Cognito のリージョン |
| `{{COGNITO_USER_POOL_ID}}` | User Pool ID |
| `{{COGNITO_CLIENT_ID}}` | App Client ID |
| `{{COGNITO_CLIENT_SECRET}}` | App Client Secret |
| `{{COGNITO_DOMAIN}}` | Cognito ドメイン（FQDN） |
| `{{CLOUDFRONT_DOMAIN}}` | CloudFront ドメイン |

## Terraform デプロイ（代替方法）

CLI の代わりに Terraform を使用する場合：

```bash
cd iac/environments/cloudfront-cognito-s3

# 設定ファイル作成
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集

# Lambda ビルド
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

## トラブルシューティング

### ログインがリダイレクトループする

1. Cognito App Client の callback URL を確認
   ```bash
   aws cognito-idp describe-user-pool-client \
     --user-pool-id <pool-id> \
     --client-id <client-id> \
     --query 'UserPoolClient.CallbackURLs'
   ```

2. URL が `https://<cloudfront-domain>/auth/callback` と一致しているか確認

3. CloudFront のデプロイが完了しているか確認
   ```bash
   aws cloudfront get-distribution --id <dist-id> --query 'Distribution.Status'
   ```

### トークン検証エラー

1. CloudWatch Logs で Lambda@Edge のログを確認
   ```bash
   aws logs tail "/aws/lambda/us-east-1.<stack-name>-auth-check" \
     --follow --region us-east-1
   ```

2. 一般的なエラー原因：
   - `Invalid issuer`: Cognito Region または User Pool ID の設定ミス
   - `Invalid audience`: Client ID の設定ミス
   - `Token expired`: トークンの有効期限切れ（refresh が機能していない）
   - `Key not found in JWKS`: JWKS 取得の問題（ネットワーク）

### Lambda@Edge が削除できない

Lambda@Edge はレプリカが削除されるまで関数を削除できません。
レプリカの削除には最大 1 時間かかることがあります。

```bash
# しばらく待ってから再試行
./script.sh destroy <stack-name>
```

### Cookie が設定されない

1. HTTPS を使用しているか確認（Secure 属性）
2. ブラウザの開発者ツールで Set-Cookie ヘッダーを確認
3. SameSite 属性によるブロックを確認

### CORS エラー

このアーキテクチャは同一オリジン（CloudFront）で動作するため、通常 CORS は不要です。
API を別途呼び出す場合は、API 側で CORS 設定が必要です。

## 制限事項

- Lambda@Edge は **us-east-1** にデプロイされます
- Lambda@Edge の最大実行時間は viewer-request で **5 秒**
- Lambda@Edge のメモリは最大 **128 MB**（viewer-request）
- Cookie のサイズ制限（約 4KB）により、大きな JWT は問題になる可能性があります
- CloudFront のデプロイには **数分〜15分** かかります
- Lambda@Edge の削除には **最大1時間** かかることがあります

## 参考リンク

- [Amazon Cognito Hosted UI](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-app-integration.html)
- [Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-at-the-edge.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [JWT Verification](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html)
