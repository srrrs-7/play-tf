# =============================================================================
# CloudFront + Cognito + Lambda@Edge + S3 認証アーキテクチャ
# =============================================================================
# ブラウザでコンテンツURLを直接開く → 未認証なら Cognito ログイン → 認証後にコンテンツ表示
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# メインリージョン プロバイダー
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# Lambda@Edge 用 プロバイダー (us-east-1 必須)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# =============================================================================
# データソース
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# S3 バケット (コンテンツ保存用)
# =============================================================================

module "content_bucket" {
  source = "../../modules/s3"

  bucket_name         = "${var.project_name}-${var.environment}-content"
  enable_versioning   = var.enable_s3_versioning
  block_public_access = true

  lifecycle_rules = var.s3_lifecycle_rules

  tags = {
    Purpose = "Protected content storage"
  }
}

# =============================================================================
# Cognito User Pool
# =============================================================================

module "cognito" {
  source = "../../modules/cognito"

  user_pool_name = "${var.project_name}-${var.environment}-users"

  # 認証設定
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = var.mfa_configuration

  # パスワードポリシー
  password_policy = var.password_policy

  # User Pool クライアント
  create_user_pool_client = true
  user_pool_client_name   = "${var.project_name}-${var.environment}-client"
  generate_client_secret  = true

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = ["openid", "email", "profile"]

  # コールバックURL (CloudFront デプロイ後に更新が必要)
  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  # トークン有効期間
  access_token_validity  = var.access_token_validity_hours
  id_token_validity      = var.id_token_validity_hours
  refresh_token_validity = var.refresh_token_validity_days

  token_validity_units = {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Cognito ドメイン (Hosted UI)
  create_user_pool_domain = true
  user_pool_domain        = var.cognito_domain_prefix

  tags = {
    Purpose = "User authentication"
  }
}

# =============================================================================
# Lambda@Edge IAM ロール
# =============================================================================

resource "aws_iam_role" "lambda_edge" {
  provider = aws.us_east_1
  name     = "${var.project_name}-${var.environment}-edge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_edge_basic" {
  provider   = aws.us_east_1
  role       = aws_iam_role.lambda_edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# Lambda@Edge 関数
# =============================================================================

# auth-check 関数アーカイブ
data "archive_file" "auth_check" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/auth-check/dist"
  output_path = "${path.module}/builds/auth-check.zip"
}

# auth-callback 関数アーカイブ
data "archive_file" "auth_callback" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/auth-callback/dist"
  output_path = "${path.module}/builds/auth-callback.zip"
}

# auth-refresh 関数アーカイブ
data "archive_file" "auth_refresh" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/auth-refresh/dist"
  output_path = "${path.module}/builds/auth-refresh.zip"
}

# Lambda@Edge: auth-check
resource "aws_lambda_function" "auth_check" {
  provider = aws.us_east_1

  filename         = data.archive_file.auth_check.output_path
  function_name    = "${var.project_name}-${var.environment}-auth-check"
  role             = aws_iam_role.lambda_edge.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.auth_check.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 5
  memory_size      = 128
  publish          = true

  description = "CloudFront viewer-request: JWT認証チェック"
}

# Lambda@Edge: auth-callback
resource "aws_lambda_function" "auth_callback" {
  provider = aws.us_east_1

  filename         = data.archive_file.auth_callback.output_path
  function_name    = "${var.project_name}-${var.environment}-auth-callback"
  role             = aws_iam_role.lambda_edge.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.auth_callback.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 5
  memory_size      = 128
  publish          = true

  description = "CloudFront viewer-request: OAuth コールバック処理"
}

# Lambda@Edge: auth-refresh
resource "aws_lambda_function" "auth_refresh" {
  provider = aws.us_east_1

  filename         = data.archive_file.auth_refresh.output_path
  function_name    = "${var.project_name}-${var.environment}-auth-refresh"
  role             = aws_iam_role.lambda_edge.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.auth_refresh.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 5
  memory_size      = 128
  publish          = true

  description = "CloudFront viewer-request: トークンリフレッシュ"
}

# =============================================================================
# CloudFront Origin Access Control
# =============================================================================

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "OAC for ${var.project_name} content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# S3 バケットポリシー (CloudFront からのアクセスを許可)
# =============================================================================

resource "aws_s3_bucket_policy" "content_bucket" {
  bucket = module.content_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.content_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

# =============================================================================
# CloudFront Distribution
# =============================================================================

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${var.project_name}-${var.environment} protected content"
  default_root_object = var.default_root_object
  price_class         = var.cloudfront_price_class

  # S3 オリジン
  origin {
    domain_name              = module.content_bucket.regional_domain_name
    origin_id                = "S3-${module.content_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # デフォルトキャッシュビヘイビア (auth-check)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${module.content_bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward           = "whitelist"
        whitelisted_names = ["cognito_id_token", "cognito_access_token", "cognito_refresh_token"]
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.auth_check.qualified_arn
      include_body = false
    }
  }

  # /auth/callback ビヘイビア
  ordered_cache_behavior {
    path_pattern     = "/auth/callback"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${module.content_bucket.id}"

    forwarded_values {
      query_string = true
      cookies {
        forward           = "whitelist"
        whitelisted_names = ["cognito_state"]
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.auth_callback.qualified_arn
      include_body = false
    }
  }

  # /auth/refresh ビヘイビア
  ordered_cache_behavior {
    path_pattern     = "/auth/refresh"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${module.content_bucket.id}"

    forwarded_values {
      query_string = true
      cookies {
        forward           = "whitelist"
        whitelisted_names = ["cognito_refresh_token"]
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.auth_refresh.qualified_arn
      include_body = false
    }
  }

  # /auth/logout ビヘイビア (auth-check が処理)
  ordered_cache_behavior {
    path_pattern     = "/auth/logout"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${module.content_bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.auth_check.qualified_arn
      include_body = false
    }
  }

  # アクセス制限
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # SSL/TLS 設定
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # カスタムドメイン
  aliases = var.domain_aliases

  tags = {
    Purpose = "Protected content delivery"
  }
}

# =============================================================================
# CloudWatch Log Groups (Lambda@Edge ログ)
# =============================================================================

resource "aws_cloudwatch_log_group" "auth_check" {
  provider          = aws.us_east_1
  name              = "/aws/lambda/us-east-1.${aws_lambda_function.auth_check.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "auth_callback" {
  provider          = aws.us_east_1
  name              = "/aws/lambda/us-east-1.${aws_lambda_function.auth_callback.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "auth_refresh" {
  provider          = aws.us_east_1
  name              = "/aws/lambda/us-east-1.${aws_lambda_function.auth_refresh.function_name}"
  retention_in_days = var.log_retention_days
}
