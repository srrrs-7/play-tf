# CLAUDE.md - Amazon ECR

Amazon ECR リポジトリを作成するTerraformモジュール。ライフサイクルポリシー、クロスアカウントアクセス対応。

## Overview

このモジュールは以下のリソースを作成します:
- ECR Repository
- Lifecycle Policy (イメージ保持ルール)
- Repository Policy (アクセス制御)
- Replication Configuration (クロスリージョンレプリケーション)

## Key Resources

- `aws_ecr_repository.this` - ECRリポジトリ本体
- `aws_ecr_lifecycle_policy.this` - カスタムライフサイクルポリシー
- `aws_ecr_lifecycle_policy.default` - デフォルトライフサイクルポリシー
- `aws_ecr_repository_policy.this` - カスタムリポジトリポリシー
- `aws_ecr_repository_policy.cross_account` - クロスアカウントアクセス
- `aws_ecr_replication_configuration.this` - レプリケーション設定

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| repository_name | string | ECRリポジトリ名 |
| image_tag_mutability | string | イメージタグの可変性 (MUTABLE, IMMUTABLE) |
| force_delete | bool | イメージがあっても強制削除するか (default: false) |
| scan_on_push | bool | プッシュ時にスキャンするか (default: true) |
| encryption_type | string | 暗号化タイプ (AES256, KMS) |
| kms_key_arn | string | KMS暗号化用キーARN |
| lifecycle_policy | string | カスタムライフサイクルポリシーJSON |
| enable_default_lifecycle_policy | bool | デフォルトライフサイクルポリシーを有効にするか (default: true) |
| max_image_count | number | 保持する最大イメージ数 (default: 10) |
| untagged_image_retention_days | number | タグなしイメージの保持日数 (default: 7) |
| repository_policy | string | カスタムリポジトリポリシーJSON |
| allowed_account_ids | list(string) | プルを許可するAWSアカウントID |
| replication_configuration | object | レプリケーション設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | ECRリポジトリID |
| arn | ECRリポジトリARN |
| name | ECRリポジトリ名 |
| repository_url | ECRリポジトリURL |
| registry_id | レジストリID |

## Usage Example

```hcl
module "ecr" {
  source = "../../modules/ecr"

  repository_name      = "${var.project_name}-${var.environment}-app"
  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
  encryption_type      = "AES256"

  enable_default_lifecycle_policy = true
  max_image_count                 = 20
  untagged_image_retention_days   = 3

  tags = var.tags
}

# イメージのプッシュコマンド
# aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${module.ecr.repository_url}
# docker build -t ${module.ecr.repository_url}:latest .
# docker push ${module.ecr.repository_url}:latest
```

## Cross-Account Access Example

```hcl
module "ecr" {
  source = "../../modules/ecr"

  repository_name = "${var.project_name}-shared-app"

  # 別アカウントからのプル許可
  allowed_account_ids = ["123456789012", "234567890123"]

  tags = var.tags
}
```

## Important Notes

- `scan_on_push = true` でプッシュ時に脆弱性スキャン実行
- デフォルトライフサイクルポリシー:
  - `v` プレフィックスのタグ付きイメージを最大N個保持
  - タグなしイメージをN日後に削除
- `IMMUTABLE` タグは本番環境で推奨 (同一タグの上書き防止)
- クロスアカウントアクセスは `allowed_account_ids` で簡単に設定
- レプリケーションはDR用途でクロスリージョンに複製
- AES256暗号化はデフォルト、KMS暗号化でカスタムキー使用可能
