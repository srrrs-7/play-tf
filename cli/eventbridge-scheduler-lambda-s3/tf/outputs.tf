# =============================================================================
# S3 Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.data.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.data.arn
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
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda.arn
}

# =============================================================================
# Scheduler Outputs
# =============================================================================

output "schedule_name" {
  description = "EventBridge Scheduler schedule name"
  value       = aws_scheduler_schedule.main.name
}

output "schedule_arn" {
  description = "EventBridge Scheduler schedule ARN"
  value       = aws_scheduler_schedule.main.arn
}

output "schedule_expression" {
  description = "Schedule expression"
  value       = aws_scheduler_schedule.main.schedule_expression
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

# =============================================================================
# Useful Commands
# =============================================================================

output "invoke_lambda_command" {
  description = "Command to invoke Lambda manually"
  value       = <<-EOF
    aws lambda invoke \
      --function-name '${aws_lambda_function.processor.function_name}' \
      --payload '{"scheduleName": "manual-test"}' \
      --cli-binary-format raw-in-base64-out \
      /tmp/response.json && cat /tmp/response.json
  EOF
}

output "list_s3_objects_command" {
  description = "Command to list S3 objects"
  value       = "aws s3 ls s3://${aws_s3_bucket.data.id}/metrics/ --recursive"
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${var.stack_name}-processor --follow"
}

output "disable_schedule_command" {
  description = "Command to disable the schedule"
  value       = "aws scheduler update-schedule --name '${aws_scheduler_schedule.main.name}' --state DISABLED --schedule-expression '${var.schedule_expression}' --flexible-time-window Mode=OFF --target Arn=${aws_lambda_function.processor.arn},RoleArn=${aws_iam_role.scheduler.arn}"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    EventBridge Scheduler → Lambda → S3 Deployment Summary
    =============================================================================

    S3 Bucket:     ${aws_s3_bucket.data.id}
    Lambda:        ${aws_lambda_function.processor.function_name}
    Schedule:      ${aws_scheduler_schedule.main.name}
    Expression:    ${aws_scheduler_schedule.main.schedule_expression}

    Useful Commands:

    1. Invoke Lambda manually:
       aws lambda invoke \
         --function-name '${aws_lambda_function.processor.function_name}' \
         --payload '{"scheduleName": "manual-test"}' \
         --cli-binary-format raw-in-base64-out \
         /tmp/response.json && cat /tmp/response.json

    2. Check S3 for generated data:
       aws s3 ls s3://${aws_s3_bucket.data.id}/metrics/ --recursive

    3. View Lambda logs:
       aws logs tail /aws/lambda/${var.stack_name}-processor --follow

    4. Check schedule status:
       aws scheduler get-schedule --name '${aws_scheduler_schedule.main.name}'

    =============================================================================
  EOF
}
