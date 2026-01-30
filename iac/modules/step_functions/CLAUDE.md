# CLAUDE.md - Step Functions

AWS Step Functions（ステートマシン）を構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- Step Functionsステートマシン（Standard/Express）
- CloudWatch Logsグループ
- IAM実行ロール（オプション）
- カスタムIAMポリシー（オプション）

## Key Resources

- `aws_sfn_state_machine.this` - ステートマシン
- `aws_cloudwatch_log_group.this` - CloudWatch Logsグループ
- `aws_iam_role.this` - IAM実行ロール
- `aws_iam_role_policy.custom` - カスタムIAMポリシー

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | ステートマシン名（必須） |
| definition | string | ステートマシン定義JSON（必須） |
| role_arn | string | IAMロールARN（null時は自動作成） |
| type | string | タイプ（STANDARD/EXPRESS、デフォルト: STANDARD） |
| logging_configuration | object | ログ設定 |
| log_retention_days | number | ログ保持日数（デフォルト: 7） |
| tracing_enabled | bool | X-Rayトレーシング（デフォルト: false） |
| policy_statements | list(object) | 追加IAMポリシーステートメント |
| tags | map(string) | リソースタグ |

### logging_configuration オブジェクト構造

```hcl
logging_configuration = {
  include_execution_data = bool   # 実行データを含める（デフォルト: true）
  level                  = string # ALL/ERROR/FATAL/OFF（デフォルト: ALL）
}
```

## Outputs

| Output | Description |
|--------|-------------|
| state_machine_arn | ステートマシンARN |
| state_machine_name | ステートマシン名 |
| role_arn | IAMロールARN |
| log_group_arn | CloudWatch LogsグループARN |

## Usage Example

### 基本的なステートマシン

```hcl
module "step_functions" {
  source = "../../modules/step_functions"

  name = "order-processing"
  type = "STANDARD"

  definition = jsonencode({
    Comment = "Order processing workflow"
    StartAt = "ValidateOrder"
    States = {
      ValidateOrder = {
        Type     = "Task"
        Resource = module.lambda_validate.arn
        Next     = "ProcessPayment"
      }
      ProcessPayment = {
        Type     = "Task"
        Resource = module.lambda_payment.arn
        Next     = "SendNotification"
      }
      SendNotification = {
        Type     = "Task"
        Resource = module.lambda_notify.arn
        End      = true
      }
    }
  })

  policy_statements = [
    {
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        module.lambda_validate.arn,
        module.lambda_payment.arn,
        module.lambda_notify.arn
      ]
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Express ワークフロー（高スループット）

```hcl
module "step_functions_express" {
  source = "../../modules/step_functions"

  name = "realtime-processor"
  type = "EXPRESS"

  definition = jsonencode({
    Comment = "Real-time data processor"
    StartAt = "Transform"
    States = {
      Transform = {
        Type     = "Task"
        Resource = module.lambda_transform.arn
        Next     = "Store"
      }
      Store = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = module.dynamodb.name
          Item = {
            "id.$"        = "$.id"
            "data.$"      = "$.transformed"
            "timestamp.$" = "$$.State.EnteredTime"
          }
        }
        End = true
      }
    }
  })

  logging_configuration = {
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_enabled = true

  policy_statements = [
    {
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [module.lambda_transform.arn]
    },
    {
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = [module.dynamodb.arn]
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### 並列処理 + エラーハンドリング

```hcl
module "step_functions_parallel" {
  source = "../../modules/step_functions"

  name = "data-pipeline"

  definition = jsonencode({
    Comment = "Parallel data processing"
    StartAt = "Parallel"
    States = {
      Parallel = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "ProcessA"
            States = {
              ProcessA = {
                Type     = "Task"
                Resource = module.lambda_a.arn
                End      = true
              }
            }
          },
          {
            StartAt = "ProcessB"
            States = {
              ProcessB = {
                Type     = "Task"
                Resource = module.lambda_b.arn
                End      = true
              }
            }
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleError"
          }
        ]
        Next = "Aggregate"
      }
      Aggregate = {
        Type     = "Task"
        Resource = module.lambda_aggregate.arn
        End      = true
      }
      HandleError = {
        Type     = "Task"
        Resource = module.lambda_error_handler.arn
        End      = true
      }
    }
  })

  policy_statements = [
    {
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        module.lambda_a.arn,
        module.lambda_b.arn,
        module.lambda_aggregate.arn,
        module.lambda_error_handler.arn
      ]
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `role_arn = null`の場合、IAMロールが自動作成される
- 自動作成ロールには`CloudWatchLogsFullAccess`が付与（本番環境では制限推奨）
- `policy_statements`で追加のIAM権限を付与可能
- STANDARDタイプ: 長時間実行（最大1年）、状態履歴保存
- EXPRESSタイプ: 高スループット（最大5分）、ログベース履歴
- `logging_configuration.level = "ALL"`で全ログ取得（デバッグ推奨）
- `tracing_enabled = true`でX-Rayトレーシング有効化
- Amazon States Language (ASL)でワークフローを定義
- 直接統合: Lambda、DynamoDB、SNS、SQS、ECS、Glue、Athenaなど
