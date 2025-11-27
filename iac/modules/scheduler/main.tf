# EventBridge Scheduler Schedule Group
resource "aws_scheduler_schedule_group" "this" {
  count = var.create_schedule_group ? 1 : 0

  name = var.schedule_group_name

  tags = var.tags
}

# EventBridge Scheduler Schedule
resource "aws_scheduler_schedule" "this" {
  for_each = { for schedule in var.schedules : schedule.name => schedule }

  name                         = each.value.name
  group_name                   = var.create_schedule_group ? aws_scheduler_schedule_group.this[0].name : lookup(each.value, "group_name", "default")
  description                  = lookup(each.value, "description", null)
  state                        = lookup(each.value, "state", "ENABLED")
  schedule_expression          = each.value.schedule_expression
  schedule_expression_timezone = lookup(each.value, "schedule_expression_timezone", "UTC")
  start_date                   = lookup(each.value, "start_date", null)
  end_date                     = lookup(each.value, "end_date", null)
  kms_key_arn                  = lookup(each.value, "kms_key_arn", null)

  # フレキシブルタイムウィンドウ
  flexible_time_window {
    mode                      = lookup(each.value, "flexible_time_window_mode", "OFF")
    maximum_window_in_minutes = lookup(each.value, "flexible_time_window_mode", "OFF") != "OFF" ? lookup(each.value, "maximum_window_in_minutes", null) : null
  }

  # ターゲット設定
  target {
    arn      = each.value.target.arn
    role_arn = each.value.target.role_arn
    input    = lookup(each.value.target, "input", null)

    # リトライポリシー
    dynamic "retry_policy" {
      for_each = lookup(each.value.target, "retry_policy", null) != null ? [each.value.target.retry_policy] : []
      content {
        maximum_event_age_in_seconds = lookup(retry_policy.value, "maximum_event_age_in_seconds", null)
        maximum_retry_attempts       = lookup(retry_policy.value, "maximum_retry_attempts", null)
      }
    }

    # Dead Letter Queue
    dynamic "dead_letter_config" {
      for_each = lookup(each.value.target, "dead_letter_arn", null) != null ? [1] : []
      content {
        arn = each.value.target.dead_letter_arn
      }
    }

    # ECS ターゲット
    dynamic "ecs_parameters" {
      for_each = lookup(each.value.target, "ecs_parameters", null) != null ? [each.value.target.ecs_parameters] : []
      content {
        task_definition_arn         = ecs_parameters.value.task_definition_arn
        task_count                  = lookup(ecs_parameters.value, "task_count", 1)
        launch_type                 = lookup(ecs_parameters.value, "launch_type", null)
        platform_version            = lookup(ecs_parameters.value, "platform_version", null)
        group                       = lookup(ecs_parameters.value, "group", null)
        enable_ecs_managed_tags     = lookup(ecs_parameters.value, "enable_ecs_managed_tags", null)
        enable_execute_command      = lookup(ecs_parameters.value, "enable_execute_command", null)
        propagate_tags              = lookup(ecs_parameters.value, "propagate_tags", null)
        reference_id                = lookup(ecs_parameters.value, "reference_id", null)
        tags                        = lookup(ecs_parameters.value, "tags", null)

        dynamic "capacity_provider_strategy" {
          for_each = lookup(ecs_parameters.value, "capacity_provider_strategy", [])
          content {
            capacity_provider = capacity_provider_strategy.value.capacity_provider
            weight            = lookup(capacity_provider_strategy.value, "weight", null)
            base              = lookup(capacity_provider_strategy.value, "base", null)
          }
        }

        dynamic "network_configuration" {
          for_each = lookup(ecs_parameters.value, "network_configuration", null) != null ? [ecs_parameters.value.network_configuration] : []
          content {
            subnets          = network_configuration.value.subnets
            security_groups  = lookup(network_configuration.value, "security_groups", null)
            assign_public_ip = lookup(network_configuration.value, "assign_public_ip", false)
          }
        }

        dynamic "placement_constraints" {
          for_each = lookup(ecs_parameters.value, "placement_constraints", [])
          content {
            type       = placement_constraints.value.type
            expression = lookup(placement_constraints.value, "expression", null)
          }
        }

        dynamic "placement_strategy" {
          for_each = lookup(ecs_parameters.value, "placement_strategy", [])
          content {
            type  = placement_strategy.value.type
            field = lookup(placement_strategy.value, "field", null)
          }
        }
      }
    }

    # EventBridge ターゲット
    dynamic "eventbridge_parameters" {
      for_each = lookup(each.value.target, "eventbridge_parameters", null) != null ? [each.value.target.eventbridge_parameters] : []
      content {
        detail_type = eventbridge_parameters.value.detail_type
        source      = eventbridge_parameters.value.source
      }
    }

    # Kinesis ターゲット
    dynamic "kinesis_parameters" {
      for_each = lookup(each.value.target, "kinesis_parameters", null) != null ? [each.value.target.kinesis_parameters] : []
      content {
        partition_key = kinesis_parameters.value.partition_key
      }
    }

    # Lambda ターゲット（ペイロード処理）
    # Lambda は input パラメータで処理

    # SageMaker Pipeline ターゲット
    dynamic "sagemaker_pipeline_parameters" {
      for_each = lookup(each.value.target, "sagemaker_pipeline_parameters", null) != null ? [each.value.target.sagemaker_pipeline_parameters] : []
      content {
        dynamic "pipeline_parameter" {
          for_each = sagemaker_pipeline_parameters.value.pipeline_parameters
          content {
            name  = pipeline_parameter.value.name
            value = pipeline_parameter.value.value
          }
        }
      }
    }

    # SQS ターゲット
    dynamic "sqs_parameters" {
      for_each = lookup(each.value.target, "sqs_parameters", null) != null ? [each.value.target.sqs_parameters] : []
      content {
        message_group_id = sqs_parameters.value.message_group_id
      }
    }
  }
}
