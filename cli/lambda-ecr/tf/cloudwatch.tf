# =============================================================================
# CloudWatch Logs Insights - Sample Queries
# =============================================================================

resource "aws_cloudwatch_query_definition" "lambda_errors" {
  count = var.enable_logs_insights_queries ? 1 : 0

  name = "${local.name_prefix}/lambda-errors"

  log_group_names = [aws_cloudwatch_log_group.lambda.name]

  query_string = <<-EOF
    fields @timestamp, @message, @requestId
    | filter @message like /(?i)(error|exception|fail|timeout)/
    | sort @timestamp desc
    | limit 100
  EOF
}

resource "aws_cloudwatch_query_definition" "lambda_cold_starts" {
  count = var.enable_logs_insights_queries ? 1 : 0

  name = "${local.name_prefix}/cold-starts"

  log_group_names = [aws_cloudwatch_log_group.lambda.name]

  query_string = <<-EOF
    filter @type = "REPORT"
    | fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
    | filter @message like /Init Duration/
    | parse @message /Init Duration: (?<initDuration>[\d.]+) ms/
    | sort @timestamp desc
    | limit 50
  EOF
}

resource "aws_cloudwatch_query_definition" "lambda_performance" {
  count = var.enable_logs_insights_queries ? 1 : 0

  name = "${local.name_prefix}/performance"

  log_group_names = [aws_cloudwatch_log_group.lambda.name]

  query_string = <<-EOF
    filter @type = "REPORT"
    | stats avg(@duration) as avg_duration,
            max(@duration) as max_duration,
            min(@duration) as min_duration,
            avg(@maxMemoryUsed) as avg_memory,
            count(*) as invocations
      by bin(5m)
    | sort @timestamp desc
  EOF
}

resource "aws_cloudwatch_query_definition" "lambda_all_logs" {
  count = var.enable_logs_insights_queries ? 1 : 0

  name = "${local.name_prefix}/all-logs"

  log_group_names = [aws_cloudwatch_log_group.lambda.name]

  query_string = <<-EOF
    fields @timestamp, @message, @requestId
    | sort @timestamp desc
    | limit 200
  EOF
}

resource "aws_cloudwatch_query_definition" "lambda_reports" {
  count = var.enable_logs_insights_queries ? 1 : 0

  name = "${local.name_prefix}/execution-reports"

  log_group_names = [aws_cloudwatch_log_group.lambda.name]

  query_string = <<-EOF
    filter @type = "REPORT"
    | fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
    | sort @timestamp desc
    | limit 100
  EOF
}

# =============================================================================
# CloudWatch Metric Filter - Error Count
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${local.name_prefix}-error-count"
  pattern        = "?ERROR ?Error ?error ?EXCEPTION ?Exception ?exception"
  log_group_name = aws_cloudwatch_log_group.lambda.name

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "${var.stack_name}/Lambda"
    value         = "1"
    default_value = "0"
  }
}

# =============================================================================
# CloudWatch Metric Filter - Timeout Count
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "timeouts" {
  name           = "${local.name_prefix}-timeout-count"
  pattern        = "Task timed out"
  log_group_name = aws_cloudwatch_log_group.lambda.name

  metric_transformation {
    name          = "TimeoutCount"
    namespace     = "${var.stack_name}/Lambda"
    value         = "1"
    default_value = "0"
  }
}
