# =============================================================================
# S3 Outputs
# =============================================================================

output "source_bucket_name" {
  description = "Source S3 bucket name"
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "Source S3 bucket ARN"
  value       = aws_s3_bucket.source.arn
}

output "dest_bucket_name" {
  description = "Destination S3 bucket name"
  value       = aws_s3_bucket.dest.id
}

output "dest_bucket_arn" {
  description = "Destination S3 bucket ARN"
  value       = aws_s3_bucket.dest.arn
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

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "lambda_log_group_name" {
  description = "Lambda CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

# =============================================================================
# Useful Commands
# =============================================================================

output "upload_test_file_command" {
  description = "Command to upload a test file"
  value       = <<-EOF
echo '{"test": "data"}' | aws s3 cp - s3://${aws_s3_bucket.source.id}/${var.trigger_prefix}test.json
EOF
}

output "list_source_bucket_command" {
  description = "Command to list source bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.source.id}/ --recursive"
}

output "list_dest_bucket_command" {
  description = "Command to list destination bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.dest.id}/ --recursive"
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix} --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    S3 → Lambda → S3 Deployment Summary
    =============================================================================

    Source Bucket:      ${aws_s3_bucket.source.id}
    Destination Bucket: ${aws_s3_bucket.dest.id}
    Lambda Function:    ${aws_lambda_function.main.function_name}

    Trigger Configuration:
    - Events: ${join(", ", var.trigger_events)}
    - Prefix: ${var.trigger_prefix}
    - Suffix: ${var.trigger_suffix != "" ? var.trigger_suffix : "(any)"}

    Test Commands:
    # Upload a test file
    echo '{"test": "data"}' | aws s3 cp - s3://${aws_s3_bucket.source.id}/${var.trigger_prefix}test.json

    # Check output
    aws s3 ls s3://${aws_s3_bucket.dest.id}/ --recursive

    # View Lambda logs
    aws logs tail /aws/lambda/${local.name_prefix} --follow

    =============================================================================
  EOF
}
