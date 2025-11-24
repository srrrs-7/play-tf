output "app_bucket_id" {
  description = "Application bucket ID"
  value       = module.app_bucket.bucket_id
}

output "app_bucket_arn" {
  description = "Application bucket ARN"
  value       = module.app_bucket.bucket_arn
}

output "logs_bucket_id" {
  description = "Logs bucket ID"
  value       = module.logs_bucket.bucket_id
}

output "static_bucket_id" {
  description = "Static content bucket ID"
  value       = module.static_bucket.bucket_id
}

output "static_bucket_domain" {
  description = "Static content bucket domain"
  value       = module.static_bucket.bucket_domain_name
}
