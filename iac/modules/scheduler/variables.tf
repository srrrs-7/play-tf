variable "create_schedule_group" {
  description = "Whether to create a schedule group"
  type        = bool
  default     = false
}

variable "schedule_group_name" {
  description = "Name of the schedule group"
  type        = string
  default     = null
}

variable "schedules" {
  description = "List of EventBridge Scheduler schedules"
  type = list(object({
    name                         = string
    group_name                   = optional(string)
    description                  = optional(string)
    state                        = optional(string)
    schedule_expression          = string
    schedule_expression_timezone = optional(string)
    start_date                   = optional(string)
    end_date                     = optional(string)
    kms_key_arn                  = optional(string)

    # フレキシブルタイムウィンドウ
    flexible_time_window_mode = optional(string)
    maximum_window_in_minutes = optional(number)

    # ターゲット設定
    target = object({
      arn      = string
      role_arn = string
      input    = optional(string)

      # リトライポリシー
      retry_policy = optional(object({
        maximum_event_age_in_seconds = optional(number)
        maximum_retry_attempts       = optional(number)
      }))

      # Dead Letter Queue
      dead_letter_arn = optional(string)

      # ECS パラメータ
      ecs_parameters = optional(object({
        task_definition_arn     = string
        task_count              = optional(number)
        launch_type             = optional(string)
        platform_version        = optional(string)
        group                   = optional(string)
        enable_ecs_managed_tags = optional(bool)
        enable_execute_command  = optional(bool)
        propagate_tags          = optional(string)
        reference_id            = optional(string)
        tags                    = optional(map(string))

        capacity_provider_strategy = optional(list(object({
          capacity_provider = string
          weight            = optional(number)
          base              = optional(number)
        })))

        network_configuration = optional(object({
          subnets          = list(string)
          security_groups  = optional(list(string))
          assign_public_ip = optional(bool)
        }))

        placement_constraints = optional(list(object({
          type       = string
          expression = optional(string)
        })))

        placement_strategy = optional(list(object({
          type  = string
          field = optional(string)
        })))
      }))

      # EventBridge パラメータ
      eventbridge_parameters = optional(object({
        detail_type = string
        source      = string
      }))

      # Kinesis パラメータ
      kinesis_parameters = optional(object({
        partition_key = string
      }))

      # SageMaker Pipeline パラメータ
      sagemaker_pipeline_parameters = optional(object({
        pipeline_parameters = list(object({
          name  = string
          value = string
        }))
      }))

      # SQS パラメータ
      sqs_parameters = optional(object({
        message_group_id = string
      }))
    })
  }))
  default = []

  validation {
    condition = alltrue([
      for schedule in var.schedules : schedule.state == null || contains(["ENABLED", "DISABLED"], schedule.state)
    ])
    error_message = "Schedule state must be ENABLED or DISABLED."
  }

  validation {
    condition = alltrue([
      for schedule in var.schedules : schedule.flexible_time_window_mode == null || contains(["OFF", "FLEXIBLE"], schedule.flexible_time_window_mode)
    ])
    error_message = "flexible_time_window_mode must be OFF or FLEXIBLE."
  }
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
