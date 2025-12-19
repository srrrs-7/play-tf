# =============================================================================
# ECR Outputs
# =============================================================================

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.main.arn
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.main.name
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Lambda function name"
  value       = var.create_lambda_function ? aws_lambda_function.main[0].function_name : null
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = var.create_lambda_function ? aws_lambda_function.main[0].arn : null
}

output "lambda_function_url" {
  description = "Lambda function URL (if API Gateway not enabled)"
  value       = var.create_lambda_function && !var.create_api_gateway ? aws_lambda_function_url.main[0].function_url : null
}

output "lambda_invoke_arn" {
  description = "Lambda invoke ARN"
  value       = var.create_lambda_function ? aws_lambda_function.main[0].invoke_arn : null
}

# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = var.create_api_gateway && var.create_lambda_function ? aws_apigatewayv2_stage.main[0].invoke_url : null
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = var.create_api_gateway && var.create_lambda_function ? aws_apigatewayv2_api.main[0].id : null
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Lambda execution role name"
  value       = aws_iam_role.lambda_execution.name
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = aws_cloudwatch_log_group.lambda.arn
}

# =============================================================================
# Useful Commands
# =============================================================================

output "ecr_login_command" {
  description = "Command to login to ECR"
  value       = "aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}

output "docker_build_command" {
  description = "Command to build Docker image"
  value       = "docker build --platform linux/amd64 -t ${var.stack_name}:latest ../src/"
}

output "docker_push_commands" {
  description = "Commands to tag and push Docker image"
  value       = <<-EOF
    # Tag image
    docker tag ${var.stack_name}:latest ${aws_ecr_repository.main.repository_url}:latest

    # Push image
    docker push ${aws_ecr_repository.main.repository_url}:latest
  EOF
}

output "create_lambda_command" {
  description = "Terraform command to create Lambda function after pushing image"
  value       = "terraform apply -var='create_lambda_function=true'"
}

output "lambda_invoke_command" {
  description = "Command to invoke Lambda function"
  value       = var.create_lambda_function ? "aws lambda invoke --function-name ${aws_lambda_function.main[0].function_name} --payload '{\"key\": \"value\"}' --cli-binary-format raw-in-base64-out /dev/stdout" : "Lambda function not created yet"
}

output "lambda_update_command" {
  description = "Command to update Lambda function with new image"
  value       = var.create_lambda_function ? "aws lambda update-function-code --function-name ${aws_lambda_function.main[0].function_name} --image-uri ${aws_ecr_repository.main.repository_url}:latest" : "Lambda function not created yet"
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${var.stack_name} --follow"
}

output "logs_insights_console_url" {
  description = "CloudWatch Logs Insights console URL"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:logs-insights?queryDetail=~(editorString~'fields*20*40timestamp*2c*20*40message*0a*7c*20sort*20*40timestamp*20desc*0a*7c*20limit*20200~source~(~'*2faws*2flambda*2f${var.stack_name}))"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    Lambda + ECR Container Image Deployment Summary
    =============================================================================

    ECR Repository: ${aws_ecr_repository.main.repository_url}
    Log Group:      /aws/lambda/${var.stack_name}
    ${var.create_lambda_function ? "Lambda:         ${aws_lambda_function.main[0].function_name}" : "Lambda:         Not created yet (run: terraform apply -var='create_lambda_function=true')"}
    ${var.create_lambda_function && var.create_api_gateway ? "API Endpoint:   ${aws_apigatewayv2_stage.main[0].invoke_url}" : ""}
    ${var.create_lambda_function && !var.create_api_gateway ? "Function URL:   ${aws_lambda_function_url.main[0].function_url}" : ""}

    Next Steps:
    1. Login to ECR:
       aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com

    2. Build and push container image:
       docker build --platform linux/amd64 -t ${var.stack_name}:latest ../src/
       docker tag ${var.stack_name}:latest ${aws_ecr_repository.main.repository_url}:latest
       docker push ${aws_ecr_repository.main.repository_url}:latest

    3. Create Lambda function:
       terraform apply -var='create_lambda_function=true'

    4. Invoke function:
       aws lambda invoke --function-name ${var.stack_name} --payload '{"key": "value"}' --cli-binary-format raw-in-base64-out /dev/stdout

    5. Update function (after code changes):
       docker build --platform linux/amd64 -t ${var.stack_name}:latest ../src/
       docker tag ${var.stack_name}:latest ${aws_ecr_repository.main.repository_url}:latest
       docker push ${aws_ecr_repository.main.repository_url}:latest
       aws lambda update-function-code --function-name ${var.stack_name} --image-uri ${aws_ecr_repository.main.repository_url}:latest

    6. View logs:
       aws logs tail /aws/lambda/${var.stack_name} --follow

    =============================================================================
  EOF
}

output "logs_insights_sample_queries" {
  description = "Sample CloudWatch Logs Insights queries"
  value       = <<-EOF

    =============================================================================
    CloudWatch Logs Insights Sample Queries for Lambda
    =============================================================================

    1. View all logs (latest):
    -------------------------
    fields @timestamp, @message, @requestId
    | sort @timestamp desc
    | limit 200

    2. Search for errors:
    ---------------------
    fields @timestamp, @message, @requestId
    | filter @message like /(?i)(error|exception|fail|timeout)/
    | sort @timestamp desc
    | limit 100

    3. Cold start analysis:
    -----------------------
    filter @type = "REPORT"
    | fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
    | filter @message like /Init Duration/
    | parse @message /Init Duration: (?<initDuration>[\d.]+) ms/
    | sort @timestamp desc

    4. Performance metrics:
    -----------------------
    filter @type = "REPORT"
    | stats avg(@duration) as avg_duration,
            max(@duration) as max_duration,
            min(@duration) as min_duration,
            avg(@maxMemoryUsed) as avg_memory,
            count(*) as invocations
      by bin(5m)

    5. Execution reports:
    ---------------------
    filter @type = "REPORT"
    | fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
    | sort @timestamp desc

    =============================================================================
  EOF
}
