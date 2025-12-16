# =============================================================================
# EventBridge Outputs
# =============================================================================

output "event_bus_name" {
  description = "EventBridge event bus name"
  value       = aws_cloudwatch_event_bus.main.name
}

output "event_bus_arn" {
  description = "EventBridge event bus ARN"
  value       = aws_cloudwatch_event_bus.main.arn
}

output "rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.order.name
}

output "rule_arn" {
  description = "EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.order.arn
}

# =============================================================================
# Step Functions Outputs
# =============================================================================

output "state_machine_name" {
  description = "Step Functions state machine name"
  value       = aws_sfn_state_machine.order_workflow.name
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.order_workflow.arn
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_names" {
  description = "Lambda function names"
  value       = { for k, v in aws_lambda_function.functions : k => v.function_name }
}

output "lambda_function_arns" {
  description = "Lambda function ARNs"
  value       = { for k, v in aws_lambda_function.functions : k => v.arn }
}

# =============================================================================
# Useful Commands
# =============================================================================

output "put_event_command" {
  description = "Command to put a test event"
  value       = <<-EOF
    aws events put-events --entries '[{
      "EventBusName": "${aws_cloudwatch_event_bus.main.name}",
      "Source": "${var.event_source}",
      "DetailType": "${var.event_detail_type}",
      "Detail": "{\"orderId\": \"ORD-001\", \"items\": [{\"name\": \"Product A\", \"price\": 29.99, \"quantity\": 2}]}"
    }]'
  EOF
}

output "list_executions_command" {
  description = "Command to list Step Functions executions"
  value       = "aws stepfunctions list-executions --state-machine-arn '${aws_sfn_state_machine.order_workflow.arn}'"
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${var.stack_name}-validate --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    EventBridge → Step Functions → Lambda Deployment Summary
    =============================================================================

    Event Bus:     ${aws_cloudwatch_event_bus.main.name}
    Rule:          ${aws_cloudwatch_event_rule.order.name}
    State Machine: ${aws_sfn_state_machine.order_workflow.name}

    Lambda Functions:
      - ${var.stack_name}-validate
      - ${var.stack_name}-payment
      - ${var.stack_name}-shipping
      - ${var.stack_name}-notify

    Test with:
      aws events put-events --entries '[{
        "EventBusName": "${aws_cloudwatch_event_bus.main.name}",
        "Source": "${var.event_source}",
        "DetailType": "${var.event_detail_type}",
        "Detail": "{\"orderId\": \"ORD-001\", \"items\": [{\"name\": \"Product A\", \"price\": 29.99, \"quantity\": 2}]}"
      }]'

    Check executions:
      aws stepfunctions list-executions --state-machine-arn '${aws_sfn_state_machine.order_workflow.arn}'

    =============================================================================
  EOF
}
