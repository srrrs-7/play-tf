# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_gateway_arn" {
  description = "API Gateway REST API ARN"
  value       = aws_api_gateway_rest_api.main.arn
}

output "api_gateway_name" {
  description = "API Gateway REST API name"
  value       = aws_api_gateway_rest_api.main.name
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "api_gateway_stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.main.stage_name
}

output "api_key_value" {
  description = "API key value (if enabled)"
  value       = var.enable_api_key ? aws_api_gateway_api_key.main[0].value : null
  sensitive   = true
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

output "lambda_invoke_arn" {
  description = "Lambda invoke ARN"
  value       = aws_lambda_function.main.invoke_arn
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

output "dynamodb_table_id" {
  description = "DynamoDB table ID"
  value       = aws_dynamodb_table.main.id
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "lambda_log_group_name" {
  description = "Lambda CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "api_gateway_log_group_name" {
  description = "API Gateway CloudWatch log group name"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway[0].name : null
}

# =============================================================================
# API Endpoints
# =============================================================================

output "items_endpoint" {
  description = "Items API endpoint (GET, POST)"
  value       = "${aws_api_gateway_stage.main.invoke_url}/items"
}

output "item_endpoint_pattern" {
  description = "Single item API endpoint pattern (GET, PUT, DELETE)"
  value       = "${aws_api_gateway_stage.main.invoke_url}/items/{id}"
}

# =============================================================================
# Useful Commands
# =============================================================================

output "curl_list_items" {
  description = "curl command to list all items"
  value       = "curl -X GET ${aws_api_gateway_stage.main.invoke_url}/items"
}

output "curl_create_item" {
  description = "curl command to create an item"
  value       = "curl -X POST ${aws_api_gateway_stage.main.invoke_url}/items -H 'Content-Type: application/json' -d '{\"name\": \"test\", \"value\": 123}'"
}

output "curl_get_item" {
  description = "curl command to get a single item"
  value       = "curl -X GET ${aws_api_gateway_stage.main.invoke_url}/items/{id}"
}

output "curl_update_item" {
  description = "curl command to update an item"
  value       = "curl -X PUT ${aws_api_gateway_stage.main.invoke_url}/items/{id} -H 'Content-Type: application/json' -d '{\"name\": \"updated\"}'"
}

output "curl_delete_item" {
  description = "curl command to delete an item"
  value       = "curl -X DELETE ${aws_api_gateway_stage.main.invoke_url}/items/{id}"
}

output "view_lambda_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix} --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    API Gateway → Lambda → DynamoDB Deployment Summary
    =============================================================================

    API Endpoint:     ${aws_api_gateway_stage.main.invoke_url}
    DynamoDB Table:   ${aws_dynamodb_table.main.name}
    Lambda Function:  ${aws_lambda_function.main.function_name}

    API Endpoints:
    - GET    /items      - List all items
    - POST   /items      - Create new item
    - GET    /items/{id} - Get single item
    - PUT    /items/{id} - Update item
    - DELETE /items/{id} - Delete item

    Test Commands:
    # List items
    curl -X GET ${aws_api_gateway_stage.main.invoke_url}/items

    # Create item
    curl -X POST ${aws_api_gateway_stage.main.invoke_url}/items \
      -H 'Content-Type: application/json' \
      -d '{"name": "test", "value": 123}'

    # View Lambda logs
    aws logs tail /aws/lambda/${local.name_prefix} --follow

    =============================================================================
  EOF
}
