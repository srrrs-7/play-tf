# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_stage.main.invoke_url}/${var.api_endpoint_path}"
}

output "api_stage_url" {
  description = "API Gateway stage URL"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "api_execution_arn" {
  description = "API Gateway execution ARN"
  value       = aws_api_gateway_rest_api.main.execution_arn
}

# =============================================================================
# SQS Outputs
# =============================================================================

output "queue_url" {
  description = "SQS Queue URL"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "SQS Queue ARN"
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "SQS Queue name"
  value       = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "Dead Letter Queue URL"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "Dead Letter Queue ARN"
  value       = aws_sqs_queue.dlq.arn
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.processor.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.processor.arn
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}

output "lambda_log_group" {
  description = "Lambda CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "apigw_role_arn" {
  description = "API Gateway IAM role ARN"
  value       = aws_iam_role.apigw.arn
}

# =============================================================================
# Test Commands
# =============================================================================

output "test_curl_command" {
  description = "curl command to test the API"
  value       = <<-EOF
    curl -X POST '${aws_api_gateway_stage.main.invoke_url}/${var.api_endpoint_path}' \
      -H 'Content-Type: application/json' \
      -d '{"action": "test", "data": "hello"}'
  EOF
}

output "lambda_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow"
}

output "queue_receive_command" {
  description = "Command to receive messages from queue"
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.main.url} --max-number-of-messages 10"
}

output "dlq_receive_command" {
  description = "Command to receive messages from DLQ"
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.dlq.url} --max-number-of-messages 10"
}
