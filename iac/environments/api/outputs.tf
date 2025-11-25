output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = module.api_gateway.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = module.api_gateway.id
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = module.lambda_function.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = module.lambda_function.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = module.dynamodb_table.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = module.dynamodb_table.arn
}
