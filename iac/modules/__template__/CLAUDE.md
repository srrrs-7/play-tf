# CLAUDE.md - Module Template

新しいTerraformモジュールを作成するためのテンプレート。

## Overview

このテンプレートディレクトリは新規モジュール作成の出発点です。
空の`main.tf`、`variables.tf`、`outputs.tf`ファイルが含まれています。

## Usage

### 新規モジュール作成手順

1. テンプレートをコピー
```bash
cp -r iac/modules/__template__ iac/modules/{new-module-name}
```

2. `main.tf`にリソース定義を追加
```hcl
# メインリソース
resource "aws_{service}_{resource}" "this" {
  name = var.name
  # ... リソース設定
  tags = var.tags
}
```

3. `variables.tf`に入力変数を定義
```hcl
variable "name" {
  description = "リソース名"
  type        = string
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}
```

4. `outputs.tf`に出力値を定義
```hcl
output "id" {
  description = "リソースID"
  value       = aws_{service}_{resource}.this.id
}

output "arn" {
  description = "リソースARN"
  value       = aws_{service}_{resource}.this.arn
}
```

5. 環境でテスト
```bash
cd iac/environments/dev
# main.tfにモジュール参照を追加
terraform init
terraform plan
terraform apply
```

## Module Structure Pattern

```
iac/modules/{module-name}/
├── main.tf       # リソース定義
├── variables.tf  # 入力変数
├── outputs.tf    # 出力値
└── CLAUDE.md     # モジュールドキュメント
```

## Coding Conventions

### リソース命名
- プライマリリソースは`this`または`main`を使用
- 複数リソースは`for_each`でマップ管理

### コメント
- 日本語コメントを使用（このリポジトリの規約）
```hcl
# リソースの作成
resource "aws_s3_bucket" "this" {
  # バケット名
  bucket = var.bucket_name
}
```

### 変数定義
- `description`、`type`、`default`（該当する場合）を必ず指定
- 複雑な構造にはオプショナルフィールドを使用

```hcl
variable "config" {
  description = "設定オブジェクト"
  type = object({
    name     = string
    enabled  = optional(bool, true)
    settings = optional(map(string), {})
  })
}
```

### 条件付きリソース
```hcl
resource "aws_resource" "optional" {
  count = var.enable_feature ? 1 : 0
  # ...
}
```

### 動的ブロック
```hcl
dynamic "setting" {
  for_each = var.settings
  content {
    key   = setting.key
    value = setting.value
  }
}
```

### バリデーション
```hcl
variable "instance_type" {
  type = string
  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type))
    error_message = "instance_type must be t2 or t3 series."
  }
}
```

## CLAUDE.md Template

新規モジュールのCLAUDE.mdは以下のフォーマットで作成:

```markdown
# CLAUDE.md - {Module Name}

{AWS サービスの簡単な説明}

## Overview

このモジュールは以下のリソースを作成します:
- リソース1
- リソース2

## Key Resources

- `aws_{service}_{resource}.this` - 説明

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | リソース名（必須） |
| ... | ... | ... |

## Outputs

| Output | Description |
|--------|-------------|
| id | リソースID |
| ... | ... |

## Usage Example

\`\`\`hcl
module "{module_name}" {
  source = "../../modules/{module_name}"
  # ...
}
\`\`\`

## Important Notes

- 重要な考慮事項
- セキュリティのデフォルト設定
```

## Best Practices

- セキュリティのデフォルト（暗号化有効、パブリックアクセスブロック等）
- 適切なIAM権限（最小権限の原則）
- タグの継承（`var.tags`を全リソースに適用）
- 出力値の充実（ID、ARN、名前、エンドポイント等）
