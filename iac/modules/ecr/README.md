# AWS ECR Module

AWS ECR (Elastic Container Registry) リポジトリを作成するためのTerraformモジュールです。

## 機能

- ECRリポジトリの作成
- イメージスキャン設定
- ライフサイクルポリシーの設定（世代数または日数による古いイメージの削除）
- リポジトリポリシーの設定
- クロスリージョンレプリケーションの設定

## 使用方法

```hcl
module "ecr" {
  source = "../modules/ecr"

  name = "my-app"
  
  image_scanning_scan_on_push = true
  max_image_count             = 50
  
  allowed_account_ids = ["123456789012"]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | リポジトリ名 | `string` | n/a | yes |
| image_scanning_scan_on_push | プッシュ時にスキャンを実行するか | `bool` | `true` | no |
| image_tag_mutability | タグの変更可能性 (MUTABLE or IMMUTABLE) | `string` | `"MUTABLE"` | no |
| encryption_type | 暗号化タイプ (AES256 or KMS) | `string` | `"AES256"` | no |
| kms_key_arn | KMSキーのARN (encryption_typeがKMSの場合) | `string` | `null` | no |
| max_image_count | 保持する最大イメージ数 | `number` | `10` | no |
| untagged_image_retention_days | タグなしイメージの保持日数 | `number` | `7` | no |
| repository_policy | リポジトリポリシー (JSON) | `string` | `null` | no |
| allowed_account_ids | プルを許可するAWSアカウントIDのリスト | `list(string)` | `[]` | no |
| replication_configuration | レプリケーション設定 | `object` | `null` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| repository_name | リポジトリ名 |
| repository_url | リポジトリURL |
| repository_arn | リポジトリARN |
| registry_id | レジストリID |
