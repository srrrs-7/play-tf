# =============================================================================
# SNS Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.main.arn
}

output "sns_topic_name" {
  description = "SNS topic name"
  value       = aws_sns_topic.main.name
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_arns" {
  description = "Lambda function ARNs"
  value       = { for k, v in aws_lambda_function.main : k => v.arn }
}

output "lambda_function_names" {
  description = "Lambda function names"
  value       = { for k, v in aws_lambda_function.main : k => v.function_name }
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "lambda_log_group_names" {
  description = "Lambda CloudWatch log group names"
  value       = { for k, v in aws_cloudwatch_log_group.lambda : k => v.name }
}

# =============================================================================
# Useful Commands
# =============================================================================

output "publish_message_command" {
  description = "Command to publish a message (triggers all Lambda functions)"
  value       = <<-EOF
aws sns publish \
  --topic-arn ${aws_sns_topic.main.arn} \
  --message '{"event": "test", "data": {"key": "value"}}'
EOF
}

output "publish_with_filter_command" {
  description = "Command to publish with message attributes (for filtering)"
  value       = <<-EOF
aws sns publish \
  --topic-arn ${aws_sns_topic.main.arn} \
  --message '{"event": "test"}' \
  --message-attributes '{"type": {"DataType": "String", "StringValue": "notification"}}'
EOF
}

output "view_all_logs_command" {
  description = "Commands to view logs for all functions"
  value       = join("\n", [for k, v in aws_cloudwatch_log_group.lambda : "aws logs tail ${v.name} --follow"])
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    SNS → Lambda Fan-out Deployment Summary
    =============================================================================

    SNS Topic: ${aws_sns_topic.main.arn}

    Lambda Functions (${length(var.lambda_functions)} total):
    ${join("\n    ", [for k, v in aws_lambda_function.main : "- ${v.function_name}"])}

    Test Command:
    aws sns publish \
      --topic-arn ${aws_sns_topic.main.arn} \
      --message '{"event": "test", "data": {"key": "value"}}'

    All ${length(var.lambda_functions)} Lambda functions will be invoked in parallel!

    =============================================================================
  EOF
}
