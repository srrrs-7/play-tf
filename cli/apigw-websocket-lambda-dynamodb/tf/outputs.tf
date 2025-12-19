# =============================================================================
# API Gateway Outputs
# =============================================================================

output "websocket_api_id" {
  description = "WebSocket API ID"
  value       = aws_apigatewayv2_api.main.id
}

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint"
  value       = aws_apigatewayv2_stage.main.invoke_url
}

output "websocket_url" {
  description = "WebSocket URL (wss://)"
  value       = replace(aws_apigatewayv2_stage.main.invoke_url, "https://", "wss://")
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "connect_function_name" {
  description = "Connect Lambda function name"
  value       = aws_lambda_function.connect.function_name
}

output "disconnect_function_name" {
  description = "Disconnect Lambda function name"
  value       = aws_lambda_function.disconnect.function_name
}

output "message_function_name" {
  description = "Message Lambda function name"
  value       = aws_lambda_function.message.function_name
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}

# =============================================================================
# DynamoDB Outputs
# =============================================================================

output "connections_table_name" {
  description = "DynamoDB connections table name"
  value       = aws_dynamodb_table.connections.name
}

output "connections_table_arn" {
  description = "DynamoDB connections table ARN"
  value       = aws_dynamodb_table.connections.arn
}

# =============================================================================
# Useful Commands
# =============================================================================

output "wscat_connect_command" {
  description = "Command to connect using wscat"
  value       = "wscat -c ${replace(aws_apigatewayv2_stage.main.invoke_url, "https://", "wss://")}"
}

output "view_logs_connect_command" {
  description = "Command to view connect Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix}-connect --follow"
}

output "view_logs_message_command" {
  description = "Command to view message Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix}-message --follow"
}

output "list_connections_command" {
  description = "Command to list active connections"
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.connections.name}"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    API Gateway WebSocket → Lambda → DynamoDB Deployment Summary
    =============================================================================

    WebSocket URL: ${replace(aws_apigatewayv2_stage.main.invoke_url, "https://", "wss://")}
    Connections Table: ${aws_dynamodb_table.connections.name}

    Routes:
    - $connect    → ${aws_lambda_function.connect.function_name}
    - $disconnect → ${aws_lambda_function.disconnect.function_name}
    - $default    → ${aws_lambda_function.message.function_name}
    - sendMessage → ${aws_lambda_function.message.function_name}

    Test with wscat:
    # Install wscat
    npm install -g wscat

    # Connect
    wscat -c ${replace(aws_apigatewayv2_stage.main.invoke_url, "https://", "wss://")}

    # Send a message (after connecting)
    {"action": "sendMessage", "message": "Hello everyone!"}

    =============================================================================
  EOF
}
