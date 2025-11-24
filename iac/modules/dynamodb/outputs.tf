output "id" {
  description = "The ID of the table"
  value       = aws_dynamodb_table.this.id
}

output "arn" {
  description = "The ARN of the table"
  value       = aws_dynamodb_table.this.arn
}

output "stream_arn" {
  description = "The ARN of the Table Stream"
  value       = aws_dynamodb_table.this.stream_arn
}

output "stream_label" {
  description = "A timestamp, in ISO 8601 format, for this stream"
  value       = aws_dynamodb_table.this.stream_label
}
