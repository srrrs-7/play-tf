output "app_bucket_id" {
  description = "Application bucket ID"
  value       = module.app_bucket.bucket_id
}

output "app_bucket_arn" {
  description = "Application bucket ARN"
  value       = module.app_bucket.bucket_arn
}
