# AWS DynamoDB Module

AWS DynamoDBテーブルを作成するためのTerraformモジュールです。

## 機能

- DynamoDBテーブルの作成
- オンデマンド/プロビジョニングモードの選択
- GSI (Global Secondary Index) の設定
- LSI (Local Secondary Index) の設定
- TTL (Time To Live) の設定
- サーバーサイド暗号化の設定
- ポイントインタイムリカバリ (PITR) の設定
- DynamoDB Streamsの設定

## 使用方法

```hcl
module "dynamodb" {
  source = "../modules/dynamodb"

  name     = "my-table"
  hash_key = "id"
  
  attributes = [
    {
      name = "id"
      type = "S"
    }
  ]

  billing_mode = "PAY_PER_REQUEST"
  
  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | テーブル名 | `string` | n/a | yes |
| hash_key | ハッシュキー（パーティションキー） | `string` | n/a | yes |
| range_key | レンジキー（ソートキー） | `string` | `null` | no |
| attributes | 属性定義リスト | `list(object)` | `[]` | no |
| billing_mode | 課金モード (PROVISIONED or PAY_PER_REQUEST) | `string` | `"PAY_PER_REQUEST"` | no |
| read_capacity | 読み込みキャパシティ (PROVISIONEDのみ) | `number` | `null` | no |
| write_capacity | 書き込みキャパシティ (PROVISIONEDのみ) | `number` | `null` | no |
| ttl_enabled | TTLを有効にするか | `bool` | `false` | no |
| ttl_attribute_name | TTL属性名 | `string` | `""` | no |
| global_secondary_indexes | GSI設定リスト | `list(any)` | `[]` | no |
| local_secondary_indexes | LSI設定リスト | `list(any)` | `[]` | no |
| server_side_encryption_enabled | サーバーサイド暗号化を有効にするか | `bool` | `true` | no |
| kms_key_arn | KMSキーARN | `string` | `null` | no |
| point_in_time_recovery_enabled | PITRを有効にするか | `bool` | `false` | no |
| stream_enabled | ストリームを有効にするか | `bool` | `false` | no |
| stream_view_type | ストリームビュータイプ | `string` | `null` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | テーブルID |
| arn | テーブルARN |
| stream_arn | ストリームARN |
| stream_label | ストリームラベル |
