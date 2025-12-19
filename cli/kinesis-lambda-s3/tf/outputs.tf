# =============================================================================
# Kinesis Outputs
# =============================================================================

output "kinesis_stream_arn" {
  description = "Kinesis stream ARN"
  value       = aws_kinesis_stream.main.arn
}

output "kinesis_stream_name" {
  description = "Kinesis stream name"
  value       = aws_kinesis_stream.main.name
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
# S3 Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.main.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.main.arn
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

output "put_record_command" {
  description = "Command to put a record to Kinesis"
  value       = <<-EOF
aws kinesis put-record \
  --stream-name ${aws_kinesis_stream.main.name} \
  --partition-key "test-key" \
  --data '$(echo '{"event": "test", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | base64)'
EOF
}

output "put_records_command" {
  description = "Command to put multiple records to Kinesis"
  value       = <<-EOF
aws kinesis put-records \
  --stream-name ${aws_kinesis_stream.main.name} \
  --records '[
    {"PartitionKey": "key1", "Data": "'$(echo '{"id": 1}' | base64)'"},
    {"PartitionKey": "key2", "Data": "'$(echo '{"id": 2}' | base64)'"}
  ]'
EOF
}

output "list_s3_objects_command" {
  description = "Command to list S3 objects"
  value       = "aws s3 ls s3://${aws_s3_bucket.main.id}/${var.s3_prefix} --recursive"
}

output "view_logs_command" {
  description = "Command to view Lambda logs"
  value       = "aws logs tail /aws/lambda/${local.name_prefix} --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    Kinesis → Lambda → S3 Deployment Summary
    =============================================================================

    Kinesis Stream:   ${aws_kinesis_stream.main.name}
    Lambda Function:  ${aws_lambda_function.main.function_name}
    S3 Bucket:        ${aws_s3_bucket.main.id}
    S3 Prefix:        ${var.s3_prefix}

    Test Commands:
    # Put a test record
    DATA=$(echo '{"event": "test", "value": 123}' | base64)
    aws kinesis put-record \
      --stream-name ${aws_kinesis_stream.main.name} \
      --partition-key "test-key" \
      --data "$DATA"

    # List stored files
    aws s3 ls s3://${aws_s3_bucket.main.id}/${var.s3_prefix} --recursive

    # View Lambda logs
    aws logs tail /aws/lambda/${local.name_prefix} --follow

    =============================================================================
  EOF
}
