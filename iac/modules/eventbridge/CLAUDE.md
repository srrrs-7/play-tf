# CLAUDE.md - EventBridge

Amazon EventBridgeルールとターゲットを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- EventBridgeルール（スケジュールまたはイベントパターン）
- EventBridgeターゲット（Lambda、SQS、Step Functionsなど）

## Key Resources

- `aws_cloudwatch_event_rule.this` - EventBridgeルール
- `aws_cloudwatch_event_target.this` - EventBridgeターゲット

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | ルール名（必須） |
| description | string | ルールの説明 |
| schedule_expression | string | スケジュール式（cron/rate） |
| event_pattern | string | イベントパターン（JSON） |
| is_enabled | bool | ルール有効化（デフォルト: true） |
| targets | list(object) | ターゲットリスト |
| tags | map(string) | リソースタグ |

### targets オブジェクト構造

```hcl
targets = [
  {
    arn        = string           # ターゲットARN（必須）
    target_id  = optional(string) # ターゲットID
    role_arn   = optional(string) # IAMロールARN
    input      = optional(string) # 入力JSON
    input_path = optional(string) # 入力パス
    input_transformer = optional(object({
      input_paths    = map(string)
      input_template = string
    }))
    retry_policy = optional(object({
      maximum_event_age_in_seconds = number
      maximum_retry_attempts       = number
    }))
    dead_letter_arn = optional(string) # DLQ ARN
  }
]
```

## Outputs

| Output | Description |
|--------|-------------|
| rule_arn | EventBridgeルールのARN |
| rule_name | EventBridgeルールの名前 |

## Usage Example

### スケジュールベースの実行

```hcl
module "eventbridge_scheduled" {
  source = "../../modules/eventbridge"

  name                = "daily-cleanup"
  description         = "Daily cleanup job"
  schedule_expression = "cron(0 2 * * ? *)"  # 毎日2:00 UTC

  targets = [
    {
      arn      = module.lambda.arn
      role_arn = aws_iam_role.eventbridge.arn
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### イベントパターンベースの実行

```hcl
module "eventbridge_pattern" {
  source = "../../modules/eventbridge"

  name        = "s3-event-handler"
  description = "Handle S3 object creation events"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = ["my-bucket"]
      }
    }
  })

  targets = [
    {
      arn = module.step_functions.state_machine_arn
      role_arn = aws_iam_role.eventbridge.arn
      input_transformer = {
        input_paths = {
          bucket = "$.detail.bucket.name"
          key    = "$.detail.object.key"
        }
        input_template = "{\"bucket\": <bucket>, \"key\": <key>}"
      }
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `schedule_expression`と`event_pattern`は排他的（どちらか一方を指定）
- スケジュール式: `cron(分 時 日 月 曜日 年)`または`rate(値 単位)`
- ターゲットには適切なIAMロールが必要（Lambda以外の場合）
- `retry_policy`でリトライ設定をカスタマイズ可能
- `dead_letter_arn`でSQSのDLQを指定可能
