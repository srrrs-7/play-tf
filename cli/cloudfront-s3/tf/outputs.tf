# =============================================================================
# S3 Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.static.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.static.arn
}

output "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.static.bucket_regional_domain_name
}

# =============================================================================
# CloudFront Outputs
# =============================================================================

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID (for Route53 alias)"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "website_url" {
  description = "Website URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "custom_domain_url" {
  description = "Custom domain URL (if configured)"
  value       = length(var.domain_names) > 0 ? "https://${var.domain_names[0]}" : null
}

# =============================================================================
# OAC Output
# =============================================================================

output "oac_id" {
  description = "CloudFront Origin Access Control ID"
  value       = aws_cloudfront_origin_access_control.main.id
}

# =============================================================================
# Useful Commands
# =============================================================================

output "s3_sync_command" {
  description = "Command to sync local directory to S3"
  value       = "aws s3 sync ./dist s3://${aws_s3_bucket.static.id} --delete"
}

output "cloudfront_invalidate_command" {
  description = "Command to invalidate CloudFront cache"
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths '/*'"
}

output "deployment_commands" {
  description = "Complete deployment commands"
  value       = <<-EOF
    # 1. Sync files to S3
    aws s3 sync ./dist s3://${aws_s3_bucket.static.id} --delete

    # 2. Invalidate CloudFront cache
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths '/*'
  EOF
}
