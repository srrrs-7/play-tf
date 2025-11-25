# S3 環境 - 署名付き URL 払い出し機能

この環境は、S3 バケットと署名付き URL を生成する Lambda 関数、API Gateway を統合したセットアップです。

## アーキテクチャ

```
Client
  ↓ (1) Request presigned URL
API Gateway
  ↓
Lambda Function (s3-presigned-url)
  ↓ (2) Generate presigned URL
S3 Bucket
  ↑ (3) Direct upload/download using presigned URL
Client
```

## 主な機能

1. **S3 バケット**: バージョニング、ライフサイクルルール付き
2. **署名付き URL 生成 Lambda**: TypeScript 実装
3. **API Gateway**: Lambda を公開する REST API
4. **セキュリティ**: IAM ベースのアクセス制御、CORS サポート

## デプロイ手順

### 1. Lambda 関数のビルド

```bash
cd s3-presigned-url
./build.sh
cd ..
```

### 2. Terraform 変数の設定

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集：

```hcl
project_name = "myapp"
environment  = "dev"
aws_region   = "ap-northeast-1"

# 署名付き URL のデフォルト有効期限（秒）
presigned_url_default_expiration = 3600  # 1時間

# API Gateway 設定
api_authorization_type = "NONE"  # 本番環境では "AWS_IAM" を推奨
api_cors_allow_origin  = "'*'"   # 本番環境では特定のドメインを指定
```

### 3. Terraform の実行

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

### 4. API エンドポイントの確認

```bash
terraform output presigned_url_api_endpoint
```

## 使用方法

### アップロード用 URL の取得

```bash
curl -X POST https://YOUR-API-URL/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "key": "uploads/myfile.jpg",
    "operation": "upload",
    "contentType": "image/jpeg",
    "expiresIn": 300
  }'
```

レスポンス：
```json
{
  "url": "https://myapp-dev-app.s3.amazonaws.com/uploads/myfile.jpg?X-Amz-Algorithm=...",
  "key": "uploads/myfile.jpg",
  "operation": "upload",
  "expiresIn": 300,
  "bucket": "myapp-dev-app"
}
```

### ファイルのアップロード

取得した URL を使用してファイルをアップロード：

```bash
curl -X PUT "PRESIGNED-URL" \
  -H "Content-Type: image/jpeg" \
  --data-binary @myfile.jpg
```

### ダウンロード用 URL の取得

```bash
curl -X POST https://YOUR-API-URL/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "key": "uploads/myfile.jpg",
    "operation": "download",
    "expiresIn": 300
  }'
```

### ファイルのダウンロード

```bash
curl -o downloaded-file.jpg "PRESIGNED-URL"
```

## カスタマイズ

### S3 バケット設定

`main.tf` の `app_bucket` モジュールで設定をカスタマイズ：

```hcl
module "app_bucket" {
  source = "../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-app"
  enable_versioning = true
  enable_lifecycle  = true

  # ブロックパブリックアクセスの無効化（必要な場合のみ）
  block_public_access = false

  # CORS ルールの追加
  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "PUT", "POST"]
      allowed_origins = ["https://yourdomain.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ]
}
```

### 署名付き URL の有効期限

```hcl
# terraform.tfvars
presigned_url_default_expiration = 1800  # 30分
```

### 認証の追加

```hcl
# terraform.tfvars
api_authorization_type = "AWS_IAM"
```

クライアント側で AWS Signature Version 4 で署名：

```javascript
import { SignatureV4 } from '@aws-sdk/signature-v4';
import { HttpRequest } from '@aws-sdk/protocol-http';
import { Sha256 } from '@aws-crypto/sha256-js';

const signer = new SignatureV4({
  credentials: credentials,
  region: 'ap-northeast-1',
  service: 'execute-api',
  sha256: Sha256
});

const request = new HttpRequest({
  hostname: 'your-api-id.execute-api.ap-northeast-1.amazonaws.com',
  path: '/dev/',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    host: 'your-api-id.execute-api.ap-northeast-1.amazonaws.com'
  },
  body: JSON.stringify({
    key: 'uploads/file.jpg',
    operation: 'upload'
  })
});

const signedRequest = await signer.sign(request);
```

### Lambda のメモリとタイムアウト

```hcl
# main.tf
module "presigned_url_lambda" {
  # ... 既存の設定
  timeout     = 60      # 60秒
  memory_size = 512     # 512MB
}
```

## モニタリング

### CloudWatch Logs

```bash
# Lambda のログを確認
aws logs tail /aws/lambda/myapp-dev-presigned-url --follow

# API Gateway のログを確認
aws logs tail /aws/apigateway/myapp-dev-presigned-url-api --follow
```

### メトリクス

CloudWatch で以下のメトリクスを確認：

- **Lambda**:
  - Invocations: 実行回数
  - Errors: エラー数
  - Duration: 実行時間
  - Throttles: スロットリング数

- **API Gateway**:
  - Count: リクエスト数
  - 4XXError: クライアントエラー数
  - 5XXError: サーバーエラー数
  - Latency: レイテンシー

### アラームの設定

```hcl
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-presigned-url-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Lambda error rate is too high"

  dimensions = {
    FunctionName = module.presigned_url_lambda.function_name
  }
}
```

## セキュリティベストプラクティス

### 1. 有効期限の短縮

本番環境では短い有効期限を設定：

```hcl
presigned_url_default_expiration = 300  # 5分
```

### 2. CORS の制限

特定のドメインのみを許可：

```hcl
api_cors_allow_origin = "'https://yourdomain.com'"
```

### 3. 認証の有効化

API Gateway で AWS IAM 認証を有効化：

```hcl
api_authorization_type = "AWS_IAM"
```

### 4. ログの有効化と監視

```hcl
lambda_log_retention_days = 30  # 30日間保持
api_log_retention_days    = 30
```

### 5. S3 バケットポリシーの設定

```hcl
module "app_bucket" {
  # ... 既存の設定

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::myapp-dev-app",
          "arn:aws:s3:::myapp-dev-app/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
```

## トラブルシューティング

### Lambda がビルドされていない

```bash
cd s3-presigned-url
npm install
npm run build
```

### API が 403 エラーを返す

- Lambda の実行権限を確認
- API Gateway のデプロイが完了しているか確認
- 認証設定を確認

### S3 アップロードが失敗する

- 署名付き URL の有効期限を確認
- Content-Type ヘッダーが一致しているか確認
- S3 バケットの権限設定を確認

### CORS エラー

```hcl
# terraform.tfvars
api_enable_cors = true
api_cors_allow_origin = "'https://yourdomain.com'"
```

## コスト見積もり

### 開発環境（月間）

- S3: ~$0.10（10GB、1000リクエスト）
- Lambda: ~$0.20（100万リクエスト、256MB）
- API Gateway: ~$3.50（100万リクエスト）
- **合計: ~$3.80/月**

### 本番環境（月間、100万リクエスト想定）

- S3: ~$23（1TB、100万リクエスト）
- Lambda: ~$0.20（100万リクエスト、256MB）
- API Gateway: ~$3.50（100万リクエスト）
- **合計: ~$26.70/月**

## リソース削除

```bash
terraform destroy
```

**警告**: S3 バケット内のデータも削除されます。重要なデータは事前にバックアップしてください。

## 参考

- [Lambda 関数 README](./s3-presigned-url/README.md)
- [S3 モジュール](../../modules/s3/)
- [API Gateway モジュール](../../modules/apigateway/)
- [Lambda モジュール](../../modules/lambda/)
