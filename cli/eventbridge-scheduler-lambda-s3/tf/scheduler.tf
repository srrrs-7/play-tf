# =============================================================================
# EventBridge Scheduler
# =============================================================================

resource "aws_scheduler_schedule" "main" {
  name       = "${var.stack_name}-schedule"
  group_name = "default"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode                      = var.flexible_time_window_minutes > 0 ? "FLEXIBLE" : "OFF"
    maximum_window_in_minutes = var.flexible_time_window_minutes > 0 ? var.flexible_time_window_minutes : null
  }

  target {
    arn      = aws_lambda_function.processor.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      scheduleName = "${var.stack_name}-schedule"
      timestamp    = "$${aws:scheduler:scheduled-time}"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}
