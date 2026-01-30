# =============================================================================
# User Pool 出力
# =============================================================================

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool エンドポイント"
  value       = aws_cognito_user_pool.this.endpoint
}

output "user_pool_name" {
  description = "Cognito User Pool 名"
  value       = aws_cognito_user_pool.this.name
}

# =============================================================================
# User Pool クライアント出力
# =============================================================================

output "user_pool_client_id" {
  description = "Cognito User Pool クライアント ID"
  value       = var.create_user_pool_client ? aws_cognito_user_pool_client.this[0].id : null
}

output "user_pool_client_secret" {
  description = "Cognito User Pool クライアントシークレット"
  value       = var.create_user_pool_client && var.generate_client_secret ? aws_cognito_user_pool_client.this[0].client_secret : null
  sensitive   = true
}

output "user_pool_client_name" {
  description = "Cognito User Pool クライアント名"
  value       = var.create_user_pool_client ? aws_cognito_user_pool_client.this[0].name : null
}

# =============================================================================
# User Pool ドメイン出力
# =============================================================================

output "user_pool_domain" {
  description = "Cognito User Pool ドメイン"
  value       = var.create_user_pool_domain ? aws_cognito_user_pool_domain.this[0].domain : null
}

output "user_pool_domain_cloudfront_distribution_arn" {
  description = "Cognito User Pool ドメインの CloudFront Distribution ARN"
  value       = var.create_user_pool_domain ? aws_cognito_user_pool_domain.this[0].cloudfront_distribution_arn : null
}

output "cognito_domain_url" {
  description = "Cognito Hosted UI ドメイン URL"
  value       = var.create_user_pool_domain ? "https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com" : null
}

# =============================================================================
# OAuth エンドポイント出力
# =============================================================================

output "oauth_authorize_url" {
  description = "OAuth 認可エンドポイント URL"
  value       = var.create_user_pool_domain ? "https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize" : null
}

output "oauth_token_url" {
  description = "OAuth トークンエンドポイント URL"
  value       = var.create_user_pool_domain ? "https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token" : null
}

output "oauth_userinfo_url" {
  description = "OAuth ユーザー情報エンドポイント URL"
  value       = var.create_user_pool_domain ? "https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/userInfo" : null
}

output "oauth_logout_url" {
  description = "OAuth ログアウトエンドポイント URL"
  value       = var.create_user_pool_domain ? "https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com/logout" : null
}

output "jwks_url" {
  description = "JWKS エンドポイント URL"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}/.well-known/jwks.json"
}

# =============================================================================
# リソースサーバー出力
# =============================================================================

output "resource_server_identifiers" {
  description = "リソースサーバー識別子のマップ"
  value       = { for k, v in aws_cognito_resource_server.this : k => v.identifier }
}

# =============================================================================
# データソース
# =============================================================================

data "aws_region" "current" {}
