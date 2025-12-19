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

output "sqs_queue_name" {
  description = "SQS queue name"
  value       = aws_sqs_queue.main.name
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
# DynamoDB Outputs
# =============================================================================

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.main.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.main.arn
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

output "send_message_command" {
  description = "Command to send a test message"
  value       = <<-EOF
aws sqs send-message \
  --queue-url ${aws_sqs_queue.main.url} \
  --message-body '{"name": "test", "value": 123}'
EOF
}

output "send_batch_command" {
  description = "Command to send batch messages"
  value       = <<-EOF
aws sqs send-message-batch \
  --queue-url ${aws_sqs_queue.main.url} \
  --entries '[
    {"Id": "1", "MessageBody": "{\"name\": \"item1\"}"},
    {"Id": "2", "MessageBody": "{\"name\": \"item2\"}"}
  ]'
EOF
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix} --follow"
}

output "check_dlq_command" {
  description = "Command to check DLQ messages"
  value       = var.enable_dlq ? "aws sqs receive-message --queue-url ${aws_sqs_queue.dlq[0].url}" : "DLQ not enabled"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    SQS → Lambda → DynamoDB Deployment Summary
    =============================================================================

    SQS Queue:        ${aws_sqs_queue.main.url}
    DLQ:              ${var.enable_dlq ? aws_sqs_queue.dlq[0].url : "Not enabled"}
    Lambda Function:  ${aws_lambda_function.main.function_name}
    DynamoDB Table:   ${aws_dynamodb_table.main.name}

    Test Commands:
    # Send a test message
    aws sqs send-message \
      --queue-url ${aws_sqs_queue.main.url} \
      --message-body '{"name": "test", "value": 123}'

    # Check DynamoDB for processed items
    aws dynamodb scan --table-name ${aws_dynamodb_table.main.name}

    # View Lambda logs
    aws logs tail /aws/lambda/${local.name_prefix} --follow

    =============================================================================
  EOF
}
