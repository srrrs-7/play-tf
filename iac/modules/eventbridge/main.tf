resource "aws_cloudwatch_event_rule" "this" {
  name                = var.name
  description         = var.description
  schedule_expression = var.schedule_expression
  event_pattern       = var.event_pattern
  state               = var.is_enabled ? "ENABLED" : "DISABLED"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = { for idx, target in var.targets : idx => target }

  rule       = aws_cloudwatch_event_rule.this.name
  target_id  = try(each.value.target_id, "${var.name}-target-${each.key}")
  arn        = each.value.arn
  role_arn   = try(each.value.role_arn, null)
  input      = try(each.value.input, null)
  input_path = try(each.value.input_path, null)

  dynamic "input_transformer" {
    for_each = try(each.value.input_transformer, null) != null ? [each.value.input_transformer] : []
    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

  dynamic "retry_policy" {
    for_each = try(each.value.retry_policy, null) != null ? [each.value.retry_policy] : []
    content {
      maximum_event_age_in_seconds = retry_policy.value.maximum_event_age_in_seconds
      maximum_retry_attempts       = retry_policy.value.maximum_retry_attempts
    }
  }

  dynamic "dead_letter_config" {
    for_each = try(each.value.dead_letter_arn, null) != null ? [1] : []
    content {
      arn = each.value.dead_letter_arn
    }
  }
}
