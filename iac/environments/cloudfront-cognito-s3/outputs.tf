# =============================================================================
# CloudFront 出力
# =============================================================================

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "CloudFront ドメイン名"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_url" {
  description = "CloudFront URL"
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "cloudfront_arn" {
  description = "CloudFront Distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

# =============================================================================
# S3 出力
# =============================================================================

output "content_bucket_name" {
  description = "コンテンツバケット名"
  value       = module.content_bucket.id
}

output "content_bucket_arn" {
  description = "コンテンツバケットARN"
  value       = module.content_bucket.arn
}

# =============================================================================
# Cognito 出力
# =============================================================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = module.cognito.user_pool_arn
}

output "cognito_client_id" {
  description = "Cognito App Client ID"
  value       = module.cognito.user_pool_client_id
}

output "cognito_client_secret" {
  description = "Cognito App Client Secret"
  value       = module.cognito.user_pool_client_secret
  sensitive   = true
}

output "cognito_domain" {
  description = "Cognito Hosted UI ドメイン"
  value       = module.cognito.cognito_domain_url
}

output "cognito_login_url" {
  description = "Cognito ログインURL"
  value       = module.cognito.oauth_authorize_url
}

# =============================================================================
# Lambda@Edge 出力
# =============================================================================

output "lambda_auth_check_arn" {
  description = "auth-check Lambda ARN"
  value       = aws_lambda_function.auth_check.qualified_arn
}

output "lambda_auth_callback_arn" {
  description = "auth-callback Lambda ARN"
  value       = aws_lambda_function.auth_callback.qualified_arn
}

output "lambda_auth_refresh_arn" {
  description = "auth-refresh Lambda ARN"
  value       = aws_lambda_function.auth_refresh.qualified_arn
}

# =============================================================================
# 設定値出力 (Lambda コード注入用)
# =============================================================================

output "lambda_config_values" {
  description = "Lambda@Edge に注入する設定値"
  value = {
    COGNITO_REGION       = data.aws_region.current.name
    COGNITO_USER_POOL_ID = module.cognito.user_pool_id
    COGNITO_CLIENT_ID    = module.cognito.user_pool_client_id
    COGNITO_DOMAIN       = "${module.cognito.user_pool_domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
    CLOUDFRONT_DOMAIN    = aws_cloudfront_distribution.this.domain_name
  }
}

# =============================================================================
# 次のステップ
# =============================================================================

output "next_steps" {
  description = "デプロイ後の次のステップ"
  value       = <<-EOT

    デプロイ完了後の手順:

    1. Cognito コールバック URL を更新:
       terraform apply -var='cognito_callback_urls=["https://${aws_cloudfront_distribution.this.domain_name}/auth/callback"]' -var='cognito_logout_urls=["https://${aws_cloudfront_distribution.this.domain_name}/"]'

    2. テストユーザーを作成:
       aws cognito-idp admin-create-user --user-pool-id ${module.cognito.user_pool_id} --username your@email.com --user-attributes Name=email,Value=your@email.com Name=email_verified,Value=true

    3. コンテンツをアップロード:
       aws s3 cp test.jpg s3://${module.content_bucket.id}/

    4. ブラウザでテスト:
       https://${aws_cloudfront_distribution.this.domain_name}/test.jpg

  EOT
}
