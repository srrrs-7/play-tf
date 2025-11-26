output "distribution_id" {
  description = "CloudFrontディストリビューションID"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFrontディストリビューションARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "distribution_domain_name" {
  description = "CloudFrontディストリビューションのドメイン名"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFrontディストリビューションのホストゾーンID (Route 53用)"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "distribution_status" {
  description = "CloudFrontディストリビューションのステータス"
  value       = aws_cloudfront_distribution.main.status
}

output "distribution_etag" {
  description = "CloudFrontディストリビューションのETag"
  value       = aws_cloudfront_distribution.main.etag
}

output "origin_access_control_id" {
  description = "Origin Access Control ID"
  value       = var.create_origin_access_control ? aws_cloudfront_origin_access_control.main[0].id : null
}

output "cloudfront_function_arns" {
  description = "CloudFront Functions ARNマップ"
  value       = { for k, v in aws_cloudfront_function.main : k => v.arn }
}
