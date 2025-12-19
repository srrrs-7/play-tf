# =============================================================================
# CloudWatch Log Group for ECS
# =============================================================================

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-logs"
  })
}

# =============================================================================
# CloudWatch Logs Insights Queries
# =============================================================================

resource "aws_cloudwatch_query_definition" "error_logs" {
  name = "${local.name_prefix}/error-logs"

  log_group_names = [aws_cloudwatch_log_group.ecs.name]

  query_string = <<-EOF
    fields @timestamp, @message, @logStream
    | filter @message like /(?i)(error|exception|fail)/
    | sort @timestamp desc
    | limit 100
  EOF
}

resource "aws_cloudwatch_query_definition" "container_logs" {
  name = "${local.name_prefix}/container-logs"

  log_group_names = [aws_cloudwatch_log_group.ecs.name]

  query_string = <<-EOF
    fields @timestamp, @message, @logStream
    | sort @timestamp desc
    | limit 200
  EOF
}

resource "aws_cloudwatch_query_definition" "container_events" {
  name = "${local.name_prefix}/container-events"

  log_group_names = [aws_cloudwatch_log_group.ecs.name]

  query_string = <<-EOF
    fields @timestamp, @message, @logStream
    | filter @message like /(?i)(start|stop|health|ready|running)/
    | sort @timestamp desc
    | limit 100
  EOF
}

# =============================================================================
# CloudWatch Metric Filter (Optional)
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  count = var.enable_error_metric_filter ? 1 : 0

  name           = "${local.name_prefix}-error-count"
  log_group_name = aws_cloudwatch_log_group.ecs.name
  pattern        = "?ERROR ?error ?Error ?EXCEPTION ?exception ?Exception"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "${var.project_name}/${var.stack_name}"
    value         = "1"
    default_value = "0"
  }
}

# =============================================================================
# CloudWatch Alarm (Optional)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  count = var.enable_error_alarm ? 1 : 0

  alarm_name          = "${local.name_prefix}-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = "${var.project_name}/${var.stack_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "Alarm when error count exceeds threshold"
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-error-alarm"
  })

  depends_on = [aws_cloudwatch_log_metric_filter.error_count]
}
