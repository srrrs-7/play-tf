# AWS SQS Module

AWS SQS (Simple Queue Service) キューを作成するためのTerraformモジュールです。

## 機能

- SQSキューの作成（標準/FIFO）
- デッドレターキューの設定
- サーバーサイド暗号化 (SSE) の設定
- 可視性タイムアウト、メッセージ保持期間などの設定

## 使用方法

```hcl
module "sqs" {
  source = "../modules/sqs"

  name = "my-queue"
  
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  
  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | キュー名 | `string` | n/a | yes |
| visibility_timeout_seconds | 可視性タイムアウト（秒） | `number` | `30` | no |
| message_retention_seconds | メッセージ保持期間（秒） | `number` | `345600` | no |
| max_message_size | 最大メッセージサイズ (Bytes) | `number` | `262144` | no |
| delay_seconds | 遅延送信（秒） | `number` | `0` | no |
| receive_wait_time_seconds | ロングポーリング待機時間（秒） | `number` | `0` | no |
| policy | キューポリシー (JSON) | `string` | `null` | no |
| redrive_policy | リドライブポリシー (JSON) | `string` | `null` | no |
| fifo_queue | FIFOキューにするか | `bool` | `false` | no |
| content_based_deduplication | コンテンツベースの重複排除 | `bool` | `false` | no |
| kms_master_key_id | KMSキーID | `string` | `null` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | キューURL |
| arn | キューARN |
| name | キュー名 |
