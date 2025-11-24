output "id" {
  description = "The ID of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "The ID of the S3 bucket (deprecated, use 'id' instead)"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket (deprecated, use 'arn' instead)"
  value       = aws_s3_bucket.this.arn
}

output "domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "regional_domain_name" {
  description = "The regional domain name of the S3 bucket"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "region" {
  description = "The region of the S3 bucket"
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "The domain name of the S3 bucket (deprecated, use 'domain_name' instead)"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The regional domain name of the S3 bucket (deprecated, use 'regional_domain_name' instead)"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "The region of the S3 bucket (deprecated, use 'region' instead)"
  value       = aws_s3_bucket.this.region
}
