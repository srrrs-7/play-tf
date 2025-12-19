# =============================================================================
# AppSync Outputs
# =============================================================================

output "appsync_api_id" {
  description = "AppSync API ID"
  value       = aws_appsync_graphql_api.main.id
}

output "appsync_api_arn" {
  description = "AppSync API ARN"
  value       = aws_appsync_graphql_api.main.arn
}

output "graphql_endpoint" {
  description = "GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "realtime_endpoint" {
  description = "Realtime endpoint URL (for subscriptions)"
  value       = aws_appsync_graphql_api.main.uris["REALTIME"]
}

output "api_key" {
  description = "API key (if authentication_type is API_KEY)"
  value       = var.authentication_type == "API_KEY" ? aws_appsync_api_key.main[0].key : null
  sensitive   = true
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
# Useful Commands
# =============================================================================

output "curl_query_example" {
  description = "Example curl command for GraphQL query"
  value       = "curl -X POST ${aws_appsync_graphql_api.main.uris["GRAPHQL"]} -H 'Content-Type: application/json' -H 'x-api-key: <API_KEY>' -d '{\"query\": \"{ listItems { items { id name } } }\"}'"
}

output "curl_mutation_example" {
  description = "Example curl command for GraphQL mutation"
  value       = "curl -X POST ${aws_appsync_graphql_api.main.uris["GRAPHQL"]} -H 'Content-Type: application/json' -H 'x-api-key: <API_KEY>' -d '{\"query\": \"mutation { createItem(input: {name: \\\"Test\\\"}) { id } }\"}'"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    AppSync -> DynamoDB Deployment Summary
    =============================================================================

    GraphQL Endpoint: ${aws_appsync_graphql_api.main.uris["GRAPHQL"]}
    Realtime Endpoint: ${aws_appsync_graphql_api.main.uris["REALTIME"]}
    DynamoDB Table: ${aws_dynamodb_table.main.name}

    Authentication: ${var.authentication_type}

    GraphQL Operations:
    - Query: getItem(id), listItems(limit, nextToken)
    - Mutation: createItem(input), updateItem(input), deleteItem(id)
    - Subscription: onCreateItem, onUpdateItem, onDeleteItem

    Get API Key:
    terraform output -raw api_key

    =============================================================================
  EOF
}
