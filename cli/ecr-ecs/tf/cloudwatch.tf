# =============================================================================
# CloudWatch Logs Insights - Sample Queries
# =============================================================================
# Log Insightsで使用できるサンプルクエリを定義

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

resource "aws_cloudwatch_query_definition" "request_count" {
  name = "${local.name_prefix}/request-count-by-status"

  log_group_names = [aws_cloudwatch_log_group.ecs.name]

  query_string = <<-EOF
    fields @timestamp, @message
    | parse @message /\"status\":(?<status>\d+)/
    | stats count(*) as request_count by status
    | sort request_count desc
  EOF
}

resource "aws_cloudwatch_query_definition" "latency_analysis" {
  name = "${local.name_prefix}/latency-analysis"

  log_group_names = [aws_cloudwatch_log_group.ecs.name]

  query_string = <<-EOF
    fields @timestamp, @message
    | parse @message /\"duration\":(?<duration>[\d.]+)/
    | stats avg(duration) as avg_latency, max(duration) as max_latency, min(duration) as min_latency, count(*) as request_count by bin(5m)
    | sort @timestamp desc
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

resource "aws_cloudwatch_query_definition" "task_events" {
  name = "${local.name_prefix}/task-lifecycle"

  log_group_names = [aws_cloudwatch_log_group.ecs.name]

  query_string = <<-EOF
    fields @timestamp, @message, @logStream
    | filter @message like /(?i)(start|stop|health|ready)/
    | sort @timestamp desc
    | limit 50
  EOF
}

# =============================================================================
# CloudWatch Metric Filters (Optional - for custom metrics)
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  count = var.enable_error_metric_filter ? 1 : 0

  name           = "${local.name_prefix}-error-count"
  pattern        = "?ERROR ?Error ?error ?EXCEPTION ?Exception ?exception"
  log_group_name = aws_cloudwatch_log_group.ecs.name

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "${var.stack_name}/ECS"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "request_count" {
  count = var.enable_request_metric_filter ? 1 : 0

  name           = "${local.name_prefix}-request-count"
  pattern        = "{ $.request = * }"
  log_group_name = aws_cloudwatch_log_group.ecs.name

  metric_transformation {
    name          = "RequestCount"
    namespace     = "${var.stack_name}/ECS"
    value         = "1"
    default_value = "0"
  }
}

# =============================================================================
# CloudWatch Alarms (Optional)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  count = var.enable_error_alarm ? 1 : 0

  alarm_name          = "${local.name_prefix}-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = "${var.stack_name}/ECS"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "ECS application error count exceeded threshold"
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-error-alarm"
  })
}
