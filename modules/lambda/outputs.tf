output "function_name" {
  description = "Lambda関数名"
  value       = aws_lambda_function.main.function_name
}

output "function_arn" {
  description = "Lambda関数のARN"
  value       = aws_lambda_function.main.arn
}

output "invoke_arn" {
  description = "API GatewayなどからのInvoke ARN"
  value       = aws_lambda_function.main.invoke_arn
}

output "qualified_arn" {
  description = "バージョン付きARN"
  value       = aws_lambda_function.main.qualified_arn
}

output "version" {
  description = "最新バージョン"
  value       = aws_lambda_function.main.version
}

output "role_arn" {
  description = "実行ロールのARN"
  value       = aws_iam_role.lambda.arn
}

output "role_name" {
  description = "実行ロール名"
  value       = aws_iam_role.lambda.name
}

output "log_group_name" {
  description = "CloudWatch Logsグループ名"
  value       = var.create_log_group ? aws_cloudwatch_log_group.lambda[0].name : null
}
