output "id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.this.id
}

output "arn" {
  description = "The ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.this.arn
}

output "name" {
  description = "The name of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.this.name
}

output "uris" {
  description = "Map of URIs associated with the GraphQL API (GRAPHQL and REALTIME endpoints)"
  value       = aws_appsync_graphql_api.this.uris
}

output "graphql_endpoint" {
  description = "The GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.this.uris["GRAPHQL"]
}

output "realtime_endpoint" {
  description = "The Realtime endpoint URL for WebSocket subscriptions"
  value       = aws_appsync_graphql_api.this.uris["REALTIME"]
}

output "api_key" {
  description = "The API key (if created)"
  value       = length(aws_appsync_api_key.this) > 0 ? aws_appsync_api_key.this[0].key : null
  sensitive   = true
}

output "api_key_id" {
  description = "The API key ID (if created)"
  value       = length(aws_appsync_api_key.this) > 0 ? aws_appsync_api_key.this[0].id : null
}

output "dynamodb_datasource_arns" {
  description = "Map of DynamoDB data source names to ARNs"
  value       = { for k, v in aws_appsync_datasource.dynamodb : v.name => v.arn }
}

output "lambda_datasource_arns" {
  description = "Map of Lambda data source names to ARNs"
  value       = { for k, v in aws_appsync_datasource.lambda : v.name => v.arn }
}

output "http_datasource_arns" {
  description = "Map of HTTP data source names to ARNs"
  value       = { for k, v in aws_appsync_datasource.http : v.name => v.arn }
}

output "none_datasource_arns" {
  description = "Map of None data source names to ARNs"
  value       = { for k, v in aws_appsync_datasource.none : v.name => v.arn }
}

output "resolver_arns" {
  description = "Map of resolver type.field to ARNs"
  value       = { for k, v in aws_appsync_resolver.this : k => v.arn }
}

output "function_ids" {
  description = "Map of function names to function IDs"
  value       = { for k, v in aws_appsync_function.this : v.name => v.function_id }
}
