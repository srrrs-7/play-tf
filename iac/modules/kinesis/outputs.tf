output "id" {
  description = "The unique stream identifier"
  value       = aws_kinesis_stream.this.id
}

output "arn" {
  description = "The ARN of the Kinesis stream"
  value       = aws_kinesis_stream.this.arn
}

output "name" {
  description = "The unique stream name"
  value       = aws_kinesis_stream.this.name
}

output "shard_count" {
  description = "The number of shards in the stream"
  value       = aws_kinesis_stream.this.shard_count
}

output "stream_mode" {
  description = "The capacity mode of the stream"
  value       = aws_kinesis_stream.this.stream_mode_details[0].stream_mode
}

output "consumer_arns" {
  description = "Map of stream consumer names to their ARNs"
  value       = { for k, v in aws_kinesis_stream_consumer.this : v.name => v.arn }
}

output "consumer_ids" {
  description = "Map of stream consumer names to their IDs"
  value       = { for k, v in aws_kinesis_stream_consumer.this : v.name => v.id }
}
