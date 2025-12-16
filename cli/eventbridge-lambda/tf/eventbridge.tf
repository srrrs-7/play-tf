# =============================================================================
# EventBridge Event Bus
# =============================================================================
# カスタムイベントバス（オプション）
# デフォルトのイベントバスを使用する場合は create_custom_event_bus = false

resource "aws_cloudwatch_event_bus" "main" {
  count = var.create_custom_event_bus ? 1 : 0

  name = "${var.stack_name}-bus"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-bus"
  })
}

# =============================================================================
# EventBridge Rule
# =============================================================================
# イベントパターンに一致するイベントをLambdaにルーティング

resource "aws_cloudwatch_event_rule" "main" {
  name           = "${var.stack_name}-rule"
  description    = var.rule_description
  event_bus_name = var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].name : "default"
  event_pattern  = var.event_pattern
  state          = "ENABLED"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-rule"
  })
}

# =============================================================================
# EventBridge Target (Lambda)
# =============================================================================

resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.main.name
  event_bus_name = var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].name : "default"
  target_id      = "lambda-handler"
  arn            = aws_lambda_function.handler.arn
}

# =============================================================================
# Lambda Permission for EventBridge
# =============================================================================
# EventBridgeがLambdaを呼び出すための権限

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.main.arn
}
