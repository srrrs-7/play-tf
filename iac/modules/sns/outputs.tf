output "id" {
  description = "The ARN of the SNS topic"
  value       = aws_sns_topic.this.id
}

output "arn" {
  description = "The ARN of the SNS topic"
  value       = aws_sns_topic.this.arn
}

output "name" {
  description = "The name of the SNS topic"
  value       = aws_sns_topic.this.name
}

output "owner" {
  description = "The AWS Account ID of the SNS topic owner"
  value       = aws_sns_topic.this.owner
}

output "subscription_arns" {
  description = "List of ARNs for the subscriptions"
  value       = [for sub in aws_sns_topic_subscription.this : sub.arn]
}

output "subscription_ids" {
  description = "List of IDs for the subscriptions"
  value       = [for sub in aws_sns_topic_subscription.this : sub.id]
}
