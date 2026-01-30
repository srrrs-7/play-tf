# CLAUDE.md - SQS

Amazon Simple Queue Service (SQS)キューを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- SQSキュー（Standard/FIFO）

## Key Resources

- `aws_sqs_queue.this` - SQSキュー

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | キュー名（必須） |
| visibility_timeout_seconds | number | 可視性タイムアウト秒（デフォルト: 30） |
| message_retention_seconds | number | メッセージ保持秒（デフォルト: 345600 = 4日） |
| max_message_size | number | 最大メッセージサイズバイト（デフォルト: 262144 = 256KB） |
| delay_seconds | number | 配信遅延秒（デフォルト: 0） |
| receive_wait_time_seconds | number | ロングポーリング待機秒（デフォルト: 0） |
| policy | string | キューポリシーJSON |
| redrive_policy | string | DLQポリシーJSON |
| fifo_queue | bool | FIFOキュー（デフォルト: false） |
| content_based_deduplication | bool | コンテンツベース重複排除（デフォルト: false） |
| deduplication_scope | string | 重複排除スコープ（messageGroup/queue） |
| fifo_throughput_limit | string | FIFOスループット制限（perQueue/perMessageGroupId） |
| kms_master_key_id | string | KMSキーID |
| kms_data_key_reuse_period_seconds | number | KMSデータキー再利用秒（デフォルト: 300） |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | SQSキューURL |
| arn | SQSキューARN |
| name | SQSキュー名 |
| url | SQSキューURL |

## Usage Example

### 基本的なStandardキュー

```hcl
module "sqs" {
  source = "../../modules/sqs"

  name                       = "my-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600  # 14日

  # ロングポーリング有効化（コスト削減）
  receive_wait_time_seconds = 20

  tags = {
    Environment = "production"
  }
}
```

### FIFOキュー

```hcl
module "sqs_fifo" {
  source = "../../modules/sqs"

  name                        = "order-processing.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  visibility_timeout_seconds = 300

  tags = {
    Environment = "production"
  }
}
```

### Dead Letter Queue設定

```hcl
# DLQキュー
module "sqs_dlq" {
  source = "../../modules/sqs"

  name                      = "my-queue-dlq"
  message_retention_seconds = 1209600  # 14日

  tags = {
    Environment = "production"
  }
}

# メインキュー（DLQ設定付き）
module "sqs_main" {
  source = "../../modules/sqs"

  name                       = "my-queue"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = module.sqs_dlq.arn
    maxReceiveCount     = 3  # 3回失敗でDLQへ
  })

  tags = {
    Environment = "production"
  }
}
```

### KMS暗号化 + キューポリシー

```hcl
module "sqs_secure" {
  source = "../../modules/sqs"

  name              = "secure-queue"
  kms_master_key_id = aws_kms_key.sqs.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = "*"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = module.sns.arn
          }
        }
      }
    ]
  })

  tags = {
    Environment = "production"
  }
}
```

### Lambda Event Source Mapping用

```hcl
module "sqs_lambda" {
  source = "../../modules/sqs"

  name = "lambda-trigger-queue"

  # Lambdaタイムアウト（30秒）の6倍を推奨
  visibility_timeout_seconds = 180

  # バッチ処理用の設定
  receive_wait_time_seconds = 20

  tags = {
    Environment = "production"
  }
}

# Lambda Event Source Mapping
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = module.sqs_lambda.arn
  function_name    = module.lambda.arn
  batch_size       = 10
}
```

## Important Notes

- FIFOキュー名は`.fifo`サフィックスが必要
- `visibility_timeout_seconds`はLambdaタイムアウトの6倍を推奨
- `receive_wait_time_seconds > 0`でロングポーリング有効（コスト削減）
- `redrive_policy`でDLQを設定し、処理失敗メッセージを保存
- `maxReceiveCount`は失敗許容回数（超過でDLQへ移動）
- Standardキュー: 最大スループット無制限、順序保証なし
- FIFOキュー: 最大300 TPS（高スループット設定で3000 TPS）、厳密な順序保証
- KMS暗号化でメッセージを暗号化可能
- SNSからの受信にはキューポリシーが必要
