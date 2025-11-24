output "id" {
  description = "The ID of the DynamoDB table"
  value       = aws_dynamodb_table.this.id
}

output "arn" {
  description = "The ARN of the DynamoDB table"
  value       = aws_dynamodb_table.this.arn
}

output "name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "stream_arn" {
  description = "The ARN of the Table Stream"
  value       = aws_dynamodb_table.this.stream_arn
}

output "stream_label" {
  description = "A timestamp, in ISO 8601 format, for this stream"
  value       = aws_dynamodb_table.this.stream_label
}
