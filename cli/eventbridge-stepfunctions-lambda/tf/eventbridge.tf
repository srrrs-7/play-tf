# =============================================================================
# EventBridge Event Bus
# =============================================================================

resource "aws_cloudwatch_event_bus" "main" {
  name = "${var.stack_name}-bus"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-bus"
  })
}

# =============================================================================
# EventBridge Rule
# =============================================================================

resource "aws_cloudwatch_event_rule" "order" {
  name           = "${var.stack_name}-order-rule"
  description    = "Rule to trigger Step Functions on order events"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source        = [var.event_source]
    "detail-type" = [var.event_detail_type]
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-rule"
  })
}

# =============================================================================
# EventBridge Target (Step Functions)
# =============================================================================

resource "aws_cloudwatch_event_target" "stepfunctions" {
  rule           = aws_cloudwatch_event_rule.order.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "sfn-target"
  arn            = aws_sfn_state_machine.order_workflow.arn
  role_arn       = aws_iam_role.eventbridge.arn

  # イベントのdetail部分をStep Functionsに渡す
  input_path = "$.detail"
}
