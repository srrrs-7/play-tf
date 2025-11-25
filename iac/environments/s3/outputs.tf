output "app_bucket_id" {
  description = "Application bucket ID"
  value       = module.app_bucket.id
}

output "app_bucket_arn" {
  description = "Application bucket ARN"
  value       = module.app_bucket.arn
}

output "presigned_url_api_endpoint" {
  description = "API Gateway endpoint URL for presigned URL generation"
  value       = module.presigned_url_api.invoke_url
}

output "presigned_url_lambda_function_name" {
  description = "Lambda function name for presigned URL generation"
  value       = module.presigned_url_lambda.function_name
}

output "presigned_url_lambda_arn" {
  description = "Lambda function ARN for presigned URL generation"
  value       = module.presigned_url_lambda.arn
}
