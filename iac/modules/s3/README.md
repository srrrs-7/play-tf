# AWS S3 Module

AWS S3バケットを作成するためのTerraformモジュールです。

## 機能

- S3バケットの作成
- バージョニング設定
- 暗号化設定 (SSE-S3, SSE-KMS)
- パブリックアクセスブロック設定
- ライフサイクルルールの設定
- CORS設定
- バケットポリシーの設定
- アクセスログ設定

## 使用方法

```hcl
module "s3" {
  source = "../modules/s3"

  bucket_name = "my-app-bucket"
  versioning_enabled = true
  
  lifecycle_rules = [
    {
      id      = "expire-old-versions"
      enabled = true
      noncurrent_version_expiration_days = 90
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket_name | バケット名 | `string` | n/a | yes |
| versioning_enabled | バージョニングを有効にするか | `bool` | `true` | no |
| force_destroy | バケット削除時に中身も削除するか | `bool` | `false` | no |
| encryption_algorithm | 暗号化アルゴリズム (AES256 or aws:kms) | `string` | `"AES256"` | no |
| kms_master_key_id | KMSキーID | `string` | `null` | no |
| block_public_acls | パブリックACLをブロックするか | `bool` | `true` | no |
| block_public_policy | パブリックポリシーをブロックするか | `bool` | `true` | no |
| ignore_public_acls | パブリックACLを無視するか | `bool` | `true` | no |
| restrict_public_buckets | パブリックバケットを制限するか | `bool` | `true` | no |
| lifecycle_rules | ライフサイクルルールのリスト | `list(object)` | `[]` | no |
| bucket_policy | バケットポリシー (JSON) | `string` | `null` | no |
| cors_rules | CORSルールのリスト | `list(object)` | `[]` | no |
| logging_target_bucket | アクセスログ出力先バケット | `string` | `null` | no |
| logging_target_prefix | アクセスログ出力先プレフィックス | `string` | `"logs/"` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_id | バケットID (名前) |
| bucket_arn | バケットARN |
| bucket_domain_name | バケットドメイン名 |
| bucket_regional_domain_name | リージョナルドメイン名 |
