output "id" {
  description = "The ID of the REST API"
  value       = aws_api_gateway_rest_api.this.id
}

output "arn" {
  description = "The ARN of the REST API"
  value       = aws_api_gateway_rest_api.this.arn
}

output "execution_arn" {
  description = "The execution ARN part to be used in lambda_permission's source_arn"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "root_resource_id" {
  description = "The resource ID of the REST API's root"
  value       = aws_api_gateway_rest_api.this.root_resource_id
}

output "stage_name" {
  description = "The name of the stage"
  value       = aws_api_gateway_stage.this.stage_name
}

output "stage_arn" {
  description = "The ARN of the stage"
  value       = aws_api_gateway_stage.this.arn
}

output "invoke_url" {
  description = "The URL to invoke the API pointing to the stage"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "deployment_id" {
  description = "The ID of the deployment"
  value       = aws_api_gateway_deployment.this.id
}

output "log_group_name" {
  description = "CloudWatch Logsグループ名"
  value       = var.create_log_group ? aws_cloudwatch_log_group.api_gateway[0].name : null
}

output "log_group_arn" {
  description = "CloudWatch LogsグループのARN"
  value       = var.create_log_group ? aws_cloudwatch_log_group.api_gateway[0].arn : null
}
