# =============================================================================
# EventBridge Outputs
# =============================================================================

output "event_bus_name" {
  description = "EventBridge event bus name"
  value       = var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].name : "default"
}

output "event_bus_arn" {
  description = "EventBridge event bus ARN"
  value       = var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].arn : "arn:aws:events:${local.region}:${local.account_id}:event-bus/default"
}

output "rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.main.name
}

output "rule_arn" {
  description = "EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.main.arn
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.handler.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.handler.arn
}

output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

# =============================================================================
# Useful Commands
# =============================================================================

output "put_event_command" {
  description = "Command to put a test event"
  value       = <<-EOF
    aws events put-events --entries '[{
      "EventBusName": "${var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].name : "default"}",
      "Source": "my.application",
      "DetailType": "OrderCreated",
      "Detail": "{\"orderId\": \"123\", \"amount\": 99.99}"
    }]'
  EOF
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${var.stack_name}-handler --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    EventBridge → Lambda Deployment Summary
    =============================================================================

    Event Bus: ${var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].name : "default"}
    Rule:      ${aws_cloudwatch_event_rule.main.name}
    Lambda:    ${aws_lambda_function.handler.function_name}

    Test with:
      aws events put-events --entries '[{
        "EventBusName": "${var.create_custom_event_bus ? aws_cloudwatch_event_bus.main[0].name : "default"}",
        "Source": "my.application",
        "DetailType": "OrderCreated",
        "Detail": "{\"orderId\": \"123\", \"amount\": 99.99}"
      }]'

    View logs:
      aws logs tail /aws/lambda/${var.stack_name}-handler --follow

    =============================================================================
  EOF
}
