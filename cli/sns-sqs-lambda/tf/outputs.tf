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
# SQS Outputs
# =============================================================================

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.main.url
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.main.arn
}

output "dlq_queue_url" {
  description = "Dead letter queue URL"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_queue_arn" {
  description = "Dead letter queue ARN"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.main.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.main.arn
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "lambda_log_group_name" {
  description = "Lambda CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

# =============================================================================
# Useful Commands
# =============================================================================

output "publish_message_command" {
  description = "Command to publish a message to SNS"
  value       = <<-EOF
aws sns publish \
  --topic-arn ${aws_sns_topic.main.arn} \
  --message '{"name": "test", "value": 123}'
EOF
}

output "publish_with_attributes_command" {
  description = "Command to publish a message with attributes"
  value       = <<-EOF
aws sns publish \
  --topic-arn ${aws_sns_topic.main.arn} \
  --message '{"name": "test"}' \
  --message-attributes '{"type": {"DataType": "String", "StringValue": "notification"}}'
EOF
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix} --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    SNS → SQS → Lambda Deployment Summary
    =============================================================================

    SNS Topic:        ${aws_sns_topic.main.arn}
    SQS Queue:        ${aws_sqs_queue.main.url}
    DLQ:              ${var.enable_dlq ? aws_sqs_queue.dlq[0].url : "Not enabled"}
    Lambda Function:  ${aws_lambda_function.main.function_name}

    Test Commands:
    # Publish a message to SNS
    aws sns publish \
      --topic-arn ${aws_sns_topic.main.arn} \
      --message '{"name": "test", "value": 123}'

    # View Lambda logs
    aws logs tail /aws/lambda/${local.name_prefix} --follow

    =============================================================================
  EOF
}
