# CLAUDE.md - EventBridge Scheduler

Amazon EventBridge Schedulerを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- スケジュールグループ（オプション）
- スケジュール（Lambda、ECS、Step Functionsなどのターゲット）

## Key Resources

- `aws_scheduler_schedule_group.this` - スケジュールグループ
- `aws_scheduler_schedule.this` - スケジュール

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| create_schedule_group | bool | スケジュールグループ作成（デフォルト: false） |
| schedule_group_name | string | スケジュールグループ名 |
| schedules | list(object) | スケジュールリスト |
| tags | map(string) | リソースタグ |

### schedules オブジェクト構造

```hcl
schedules = [
  {
    name                         = string           # スケジュール名（必須）
    schedule_expression          = string           # スケジュール式（必須）
    schedule_expression_timezone = optional(string) # タイムゾーン（デフォルト: UTC）
    state                        = optional(string) # ENABLED/DISABLED
    description                  = optional(string)
    start_date                   = optional(string)
    end_date                     = optional(string)
    kms_key_arn                  = optional(string)
    flexible_time_window_mode    = optional(string) # OFF/FLEXIBLE
    maximum_window_in_minutes    = optional(number)

    target = {
      arn      = string           # ターゲットARN（必須）
      role_arn = string           # IAMロールARN（必須）
      input    = optional(string) # 入力JSON

      retry_policy = optional(object({...}))
      dead_letter_arn = optional(string)

      # ターゲット固有パラメータ
      ecs_parameters                = optional(object({...}))
      eventbridge_parameters        = optional(object({...}))
      kinesis_parameters            = optional(object({...}))
      sagemaker_pipeline_parameters = optional(object({...}))
      sqs_parameters                = optional(object({...}))
    }
  }
]
```

## Outputs

| Output | Description |
|--------|-------------|
| schedule_group_id | スケジュールグループID |
| schedule_group_arn | スケジュールグループARN |
| schedule_group_name | スケジュールグループ名 |
| schedule_ids | スケジュール名とIDのマップ |
| schedule_arns | スケジュール名とARNのマップ |
| schedule_names | スケジュール名のリスト |
| schedules | 全スケジュール詳細のマップ |

## Usage Example

### Lambda関数のスケジュール実行

```hcl
module "scheduler_lambda" {
  source = "../../modules/scheduler"

  schedules = [
    {
      name                         = "daily-cleanup"
      schedule_expression          = "cron(0 2 * * ? *)"
      schedule_expression_timezone = "Asia/Tokyo"
      description                  = "Daily cleanup job at 2:00 AM JST"

      target = {
        arn      = module.lambda.arn
        role_arn = aws_iam_role.scheduler.arn
        input    = jsonencode({ action = "cleanup" })
      }
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### ECSタスクのスケジュール実行

```hcl
module "scheduler_ecs" {
  source = "../../modules/scheduler"

  create_schedule_group = true
  schedule_group_name   = "batch-jobs"

  schedules = [
    {
      name                         = "hourly-batch"
      schedule_expression          = "rate(1 hour)"
      schedule_expression_timezone = "UTC"

      flexible_time_window_mode = "FLEXIBLE"
      maximum_window_in_minutes = 15

      target = {
        arn      = "arn:aws:ecs:ap-northeast-1:123456789012:cluster/my-cluster"
        role_arn = aws_iam_role.scheduler_ecs.arn

        ecs_parameters = {
          task_definition_arn = aws_ecs_task_definition.batch.arn
          task_count          = 1
          launch_type         = "FARGATE"
          platform_version    = "LATEST"

          network_configuration = {
            subnets          = module.vpc.private_subnet_ids
            security_groups  = [aws_security_group.ecs.id]
            assign_public_ip = false
          }
        }

        retry_policy = {
          maximum_event_age_in_seconds = 3600
          maximum_retry_attempts       = 3
        }

        dead_letter_arn = aws_sqs_queue.dlq.arn
      }
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Step Functionsのスケジュール実行

```hcl
module "scheduler_sfn" {
  source = "../../modules/scheduler"

  schedules = [
    {
      name                         = "weekly-report"
      schedule_expression          = "cron(0 9 ? * MON *)"  # 毎週月曜9:00
      schedule_expression_timezone = "Asia/Tokyo"

      target = {
        arn      = module.step_functions.state_machine_arn
        role_arn = aws_iam_role.scheduler_sfn.arn
        input    = jsonencode({
          reportType = "weekly"
          recipients = ["team@example.com"]
        })
      }
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- EventBridge Schedulerは従来のEventBridge Rulesより高機能
- `schedule_expression_timezone`で任意のタイムゾーンを指定可能（例: Asia/Tokyo）
- `flexible_time_window_mode = "FLEXIBLE"`で実行時間を分散（負荷分散）
- ターゲットには適切なIAMロールが必要
- サポートターゲット: Lambda、ECS、Step Functions、EventBridge、Kinesis、SQS、SageMaker
- `retry_policy`でリトライ設定をカスタマイズ
- `dead_letter_arn`でSQSのDLQを指定可能
- スケジュール式: `cron(分 時 日 月 曜日 年)`または`rate(値 単位)`
