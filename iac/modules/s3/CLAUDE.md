# CLAUDE.md - S3

Amazon S3バケットを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- S3バケット
- バージョニング設定
- サーバーサイド暗号化設定
- パブリックアクセスブロック
- ライフサイクルルール
- バケットポリシー
- CORS設定
- ログ設定

## Key Resources

- `aws_s3_bucket.this` - S3バケット
- `aws_s3_bucket_versioning.this` - バージョニング設定
- `aws_s3_bucket_server_side_encryption_configuration.this` - 暗号化設定
- `aws_s3_bucket_public_access_block.this` - パブリックアクセスブロック
- `aws_s3_bucket_lifecycle_configuration.this` - ライフサイクルルール
- `aws_s3_bucket_policy.this` - バケットポリシー
- `aws_s3_bucket_cors_configuration.this` - CORS設定
- `aws_s3_bucket_logging.this` - ログ設定

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| bucket_name | string | バケット名（必須） |
| enable_versioning | bool | バージョニング有効化（デフォルト: true） |
| block_public_access | bool | パブリックアクセスブロック（デフォルト: true） |
| kms_key_id | string | KMSキーID（nullでAES256） |
| enable_lifecycle | bool | ライフサイクルルール有効化（デフォルト: false） |
| lifecycle_rules | list(object) | ライフサイクルルール設定 |
| bucket_policy | string | バケットポリシーJSON |
| cors_rules | list(object) | CORSルール設定 |
| logging_target_bucket | string | ログ出力先バケット |
| logging_target_prefix | string | ログプレフィックス（デフォルト: logs/） |
| tags | map(string) | リソースタグ |

### lifecycle_rules オブジェクト構造

```hcl
lifecycle_rules = [
  {
    id                                 = string
    enabled                            = bool
    prefix                             = optional(string)
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string  # GLACIER, STANDARD_IA, etc.
    })))
  }
]
```

### cors_rules オブジェクト構造

```hcl
cors_rules = [
  {
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }
]
```

## Outputs

| Output | Description |
|--------|-------------|
| id | S3バケットID |
| arn | S3バケットARN |
| domain_name | バケットドメイン名 |
| regional_domain_name | リージョナルドメイン名 |
| region | バケットリージョン |

## Usage Example

### 基本的なバケット

```hcl
module "s3" {
  source = "../../modules/s3"

  bucket_name       = "my-app-data-bucket"
  enable_versioning = true

  tags = {
    Environment = "production"
  }
}
```

### ライフサイクルルール付きバケット

```hcl
module "s3_with_lifecycle" {
  source = "../../modules/s3"

  bucket_name       = "my-logs-bucket"
  enable_versioning = true
  enable_lifecycle  = true

  lifecycle_rules = [
    {
      id      = "archive-old-logs"
      enabled = true
      prefix  = "logs/"

      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]

      expiration_days                    = 365
      noncurrent_version_expiration_days = 30
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### CORS設定付きバケット（フロントエンド用）

```hcl
module "s3_frontend" {
  source = "../../modules/s3"

  bucket_name       = "my-frontend-assets"
  enable_versioning = true

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = ["https://example.com", "https://www.example.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### KMS暗号化 + ログ設定

```hcl
module "s3_secure" {
  source = "../../modules/s3"

  bucket_name       = "my-secure-bucket"
  enable_versioning = true
  kms_key_id        = aws_kms_key.s3.arn

  logging_target_bucket = module.s3_logs.id
  logging_target_prefix = "s3-access-logs/my-secure-bucket/"

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `block_public_access = true`がデフォルト（セキュリティ）
- `enable_versioning = true`がデフォルト（データ保護）
- 暗号化はデフォルトでAES256（KMSキー指定でKMS暗号化）
- `kms_key_id`指定時は自動的にバケットキーが有効化
- ライフサイクルルールでストレージコストを最適化
- ストレージクラス: STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER, GLACIER_IR, DEEP_ARCHIVE
- バケット名はグローバルでユニークである必要がある
