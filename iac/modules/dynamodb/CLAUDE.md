# CLAUDE.md - Amazon DynamoDB

Amazon DynamoDB テーブルを作成するTerraformモジュール。GSI/LSI、TTL、ストリームをサポート。

## Overview

このモジュールは以下のリソースを作成します:
- DynamoDB Table
- Global Secondary Index (GSI)
- Local Secondary Index (LSI)
- TTL設定
- DynamoDB Streams

## Key Resources

- `aws_dynamodb_table.this` - DynamoDBテーブル本体

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | DynamoDBテーブル名 |
| billing_mode | string | 課金モード (PAY_PER_REQUEST, PROVISIONED) |
| read_capacity | number | 読み取りキャパシティユニット (PROVISIONED時) |
| write_capacity | number | 書き込みキャパシティユニット (PROVISIONED時) |
| hash_key | string | パーティションキー属性名 |
| range_key | string | ソートキー属性名 (オプション) |
| attributes | list(object) | 属性定義リスト |
| ttl_enabled | bool | TTLを有効にするか (default: false) |
| ttl_attribute_name | string | TTL属性名 |
| global_secondary_indexes | list(any) | GSI設定リスト |
| local_secondary_indexes | list(any) | LSI設定リスト |
| server_side_encryption_enabled | bool | サーバーサイド暗号化を有効にするか (default: true) |
| kms_key_arn | string | 暗号化用KMSキーARN |
| point_in_time_recovery_enabled | bool | PITR (ポイントインタイムリカバリ) を有効にするか |
| stream_enabled | bool | DynamoDB Streamsを有効にするか (default: false) |
| stream_view_type | string | ストリームビュータイプ (KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES) |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | DynamoDBテーブルID |
| arn | DynamoDBテーブルARN |
| name | DynamoDBテーブル名 |
| stream_arn | テーブルストリームARN |
| stream_label | ストリームラベル (ISO 8601形式) |

## Usage Example

```hcl
module "dynamodb" {
  source = "../../modules/dynamodb"

  name         = "${var.project_name}-${var.environment}-items"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "id"
  range_key = "created_at"

  attributes = [
    {
      name = "id"
      type = "S"
    },
    {
      name = "created_at"
      type = "S"
    },
    {
      name = "user_id"
      type = "S"
    }
  ]

  global_secondary_indexes = [
    {
      name            = "user_id-index"
      hash_key        = "user_id"
      range_key       = "created_at"
      projection_type = "ALL"
    }
  ]

  ttl_enabled        = true
  ttl_attribute_name = "expires_at"

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery_enabled = true

  tags = var.tags
}
```

## Important Notes

- `PAY_PER_REQUEST` はサーバーレスアプリケーションに最適
- 属性定義はキー属性とインデックスキーのみ必要
- GSIはパーティションキーが異なるクエリパターンに使用
- LSIはパーティションキーが同じで異なるソートキーが必要な場合に使用
- DynamoDB Streamsは変更データキャプチャ (CDC) に使用
- サーバーサイド暗号化はデフォルトで有効 (AWSマネージドキー)
- PITRで最大35日間のポイントインタイムリカバリが可能
- 属性タイプ: S (文字列), N (数値), B (バイナリ)
