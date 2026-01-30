# CLAUDE.md - SNS

Amazon Simple Notification Service (SNS)トピックを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- SNSトピック（Standard/FIFO）
- トピックポリシー（オプション）
- サブスクリプション（Lambda、SQS、Email、HTTPなど）

## Key Resources

- `aws_sns_topic.this` - SNSトピック
- `aws_sns_topic_policy.this` - トピックポリシー
- `aws_sns_topic_subscription.this` - サブスクリプション

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | トピック名（必須） |
| display_name | string | 表示名（SMS用） |
| policy | string | トピックポリシーJSON |
| topic_policy | string | トピックポリシーリソース用JSON |
| delivery_policy | string | 配信ポリシーJSON |
| fifo_topic | bool | FIFOトピック（デフォルト: false） |
| content_based_deduplication | bool | コンテンツベース重複排除（デフォルト: false） |
| kms_master_key_id | string | KMSキーID |
| archive_policy | string | アーカイブポリシー（FIFO用） |
| tracing_config | string | トレーシング設定（PassThrough/Active） |
| subscriptions | list(object) | サブスクリプションリスト |
| tags | map(string) | リソースタグ |

### subscriptions オブジェクト構造

```hcl
subscriptions = [
  {
    protocol                        = string           # プロトコル（必須）
    endpoint                        = string           # エンドポイント（必須）
    confirmation_timeout_in_minutes = optional(number)
    delivery_policy                 = optional(string)
    endpoint_auto_confirms          = optional(bool)
    filter_policy                   = optional(string) # JSON
    filter_policy_scope             = optional(string) # MessageAttributes/MessageBody
    raw_message_delivery            = optional(bool)
    redrive_policy                  = optional(string) # JSON
    subscription_role_arn           = optional(string) # Firehose用
  }
]
```

### サポートプロトコル

- `lambda` - Lambda関数
- `sqs` - SQSキュー
- `email` - メール（テキスト）
- `email-json` - メール（JSON）
- `http` / `https` - HTTPエンドポイント
- `sms` - SMS
- `application` - モバイルプッシュ
- `firehose` - Kinesis Data Firehose

## Outputs

| Output | Description |
|--------|-------------|
| id | SNSトピックARN |
| arn | SNSトピックARN |
| name | SNSトピック名 |
| owner | トピックオーナーのAWSアカウントID |
| subscription_arns | サブスクリプションARNリスト |
| subscription_ids | サブスクリプションIDリスト |

## Usage Example

### 基本的なトピック + Lambdaサブスクリプション

```hcl
module "sns" {
  source = "../../modules/sns"

  name         = "my-notifications"
  display_name = "My App Notifications"

  subscriptions = [
    {
      protocol = "lambda"
      endpoint = module.lambda.arn
    }
  ]

  tags = {
    Environment = "production"
  }
}

# Lambda権限を追加
resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = module.sns.arn
}
```

### ファンアウトパターン（Lambda + SQS）

```hcl
module "sns_fanout" {
  source = "../../modules/sns"

  name = "order-events"

  subscriptions = [
    {
      protocol = "lambda"
      endpoint = module.lambda_processor.arn
      filter_policy = jsonencode({
        event_type = ["order.created", "order.updated"]
      })
    },
    {
      protocol             = "sqs"
      endpoint             = module.sqs_analytics.arn
      raw_message_delivery = true
      filter_policy = jsonencode({
        event_type = ["order.created"]
      })
    },
    {
      protocol = "email"
      endpoint = "alerts@example.com"
      filter_policy = jsonencode({
        priority = ["high"]
      })
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### FIFOトピック + KMS暗号化

```hcl
module "sns_fifo" {
  source = "../../modules/sns"

  name                        = "order-processing.fifo"
  fifo_topic                  = true
  content_based_deduplication = true
  kms_master_key_id           = aws_kms_key.sns.arn

  subscriptions = [
    {
      protocol = "sqs"
      endpoint = module.sqs_fifo.arn
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Dead Letter Queue設定

```hcl
module "sns_with_dlq" {
  source = "../../modules/sns"

  name = "critical-alerts"

  subscriptions = [
    {
      protocol = "lambda"
      endpoint = module.lambda.arn
      redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.dlq.arn
      })
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- FIFOトピック名は`.fifo`サフィックスが必要
- `filter_policy`でメッセージをフィルタリング可能
- `raw_message_delivery = true`でSNSメタデータなしで配信
- Lambda/SQSサブスクリプションは自動確認
- Email/HTTPサブスクリプションは手動確認が必要
- KMS暗号化でメッセージを暗号化可能
- `redrive_policy`でDLQを設定し、配信失敗メッセージを保存
- `tracing_config = "Active"`でX-Rayトレーシング有効化
