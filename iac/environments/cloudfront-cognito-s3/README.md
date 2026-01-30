# CloudFront + Cognito + Lambda@Edge + S3 認証アーキテクチャ

Terraform で管理する Cognito 認証付き CloudFront + S3 アーキテクチャ。

## アーキテクチャ概要

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
コンテンツレスポンス
```

## 前提条件

- Terraform >= 1.0
- AWS CLI 設定済み
- Node.js 18.x または Bun（Lambda ビルド用）

## デプロイ手順

### 1. 設定ファイル作成

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集
```

### 2. Lambda 関数ビルド

```bash
chmod +x build-lambdas.sh
./build-lambdas.sh
```

### 3. Terraform 実行

```bash
terraform init
terraform plan
terraform apply
```

### 4. Cognito コールバック URL 更新

CloudFront ドメインが確定したら、コールバック URL を更新：

```bash
# outputs から CloudFront ドメインを取得
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)

# terraform.tfvars を更新
cognito_callback_urls = ["https://${CLOUDFRONT_DOMAIN}/auth/callback"]
cognito_logout_urls   = ["https://${CLOUDFRONT_DOMAIN}/"]

# 再適用
terraform apply
```

### 5. Lambda 関数に設定値を注入して再ビルド

```bash
# outputs から設定値を取得
REGION=$(terraform output -json lambda_config_values | jq -r '.COGNITO_REGION')
POOL_ID=$(terraform output -json lambda_config_values | jq -r '.COGNITO_USER_POOL_ID')
CLIENT_ID=$(terraform output -json lambda_config_values | jq -r '.COGNITO_CLIENT_ID')
CLIENT_SECRET=$(terraform output -raw cognito_client_secret)
COGNITO_DOMAIN=$(terraform output -json lambda_config_values | jq -r '.COGNITO_DOMAIN')
CF_DOMAIN=$(terraform output -json lambda_config_values | jq -r '.CLOUDFRONT_DOMAIN')

# 設定値を注入してリビルド
./build-lambdas.sh "$REGION" "$POOL_ID" "$CLIENT_ID" "$CLIENT_SECRET" "$COGNITO_DOMAIN" "$CF_DOMAIN"

# Lambda を更新
terraform apply
```

### 6. テストユーザー作成

```bash
POOL_ID=$(terraform output -raw cognito_user_pool_id)

aws cognito-idp admin-create-user \
  --user-pool-id $POOL_ID \
  --username your@email.com \
  --user-attributes Name=email,Value=your@email.com Name=email_verified,Value=true \
  --temporary-password "TempPass123!"

# パスワードを永続化
aws cognito-idp admin-set-user-password \
  --user-pool-id $POOL_ID \
  --username your@email.com \
  --password "TempPass123!" \
  --permanent
```

### 7. コンテンツアップロード

```bash
BUCKET=$(terraform output -raw content_bucket_name)
aws s3 cp test.jpg s3://$BUCKET/
```

### 8. 動作確認

ブラウザで CloudFront URL にアクセス：

```
https://<cloudfront-domain>/test.jpg
```

1. Cognito ログイン画面にリダイレクト
2. テストユーザーでログイン
3. コンテンツが表示

## ディレクトリ構造

```
cloudfront-cognito-s3/
├── main.tf                    # メインリソース定義
├── variables.tf               # 変数定義
├── outputs.tf                 # 出力定義
├── terraform.tfvars.example   # 設定例
├── build-lambdas.sh           # Lambda ビルドスクリプト
├── README.md                  # このファイル
├── builds/                    # ビルドアーティファクト（gitignore）
└── lambda/                    # Lambda ソースコード
    ├── shared/                # 共通モジュール
    ├── auth-check/            # 認証チェック
    ├── auth-callback/         # OAuth コールバック
    └── auth-refresh/          # トークンリフレッシュ
```

## 変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `project_name` | プロジェクト名 | - |
| `environment` | 環境名 | `dev` |
| `cognito_domain_prefix` | Cognito ドメインプレフィックス | - |
| `mfa_configuration` | MFA 設定 | `OFF` |
| `cloudfront_price_class` | 価格クラス | `PriceClass_200` |

詳細は `variables.tf` を参照。

## 出力

| 出力 | 説明 |
|------|------|
| `cloudfront_url` | CloudFront URL |
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_client_id` | Cognito Client ID |
| `content_bucket_name` | S3 バケット名 |

詳細は `outputs.tf` を参照。

## セキュリティ

- S3 バケットは完全非公開（OAC 経由のみアクセス可能）
- JWT トークンは JWKS で検証
- Cookie は HttpOnly, Secure, SameSite 設定
- CSRF 対策として state パラメータを使用

## トラブルシューティング

### Lambda@Edge のログを確認

```bash
aws logs tail "/aws/lambda/us-east-1.<project>-<env>-auth-check" --follow --region us-east-1
```

### CloudFront キャッシュ無効化

```bash
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

## 削除

```bash
# S3 バケットを空にする
BUCKET=$(terraform output -raw content_bucket_name)
aws s3 rm s3://$BUCKET --recursive

# リソース削除
terraform destroy
```

**注意**: Lambda@Edge のレプリカ削除には最大1時間かかることがあります。
