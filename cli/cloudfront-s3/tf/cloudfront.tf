# =============================================================================
# CloudFront Origin Access Control (OAC)
# =============================================================================
# OAI（Origin Access Identity）は非推奨のため、OACを使用
# OACはより細かいアクセス制御とSSE-KMS対応

resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${local.name_prefix}-oac"
  description                       = "OAC for S3 bucket ${local.s3_bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# CloudFront Distribution
# =============================================================================

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront for S3 ${var.stack_name}"
  default_root_object = var.index_document
  price_class         = var.price_class

  # カスタムドメイン（オプション）
  aliases = length(var.domain_names) > 0 ? var.domain_names : null

  # =============================================================================
  # Origin Configuration
  # =============================================================================
  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.static.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  # =============================================================================
  # Default Cache Behavior
  # =============================================================================
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.static.id}"
    viewer_protocol_policy = var.viewer_protocol_policy

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    compress = var.compress

    # キャッシュポリシー（Managed-CachingOptimized）
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    # オリジンリクエストポリシー（Managed-CORS-S3Origin）
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  }

  # =============================================================================
  # Custom Error Responses (SPA Support)
  # =============================================================================
  dynamic "custom_error_response" {
    for_each = var.enable_spa_mode ? [403, 404] : []
    content {
      error_code            = custom_error_response.value
      response_code         = 200
      response_page_path    = "/${var.index_document}"
      error_caching_min_ttl = var.spa_error_caching_min_ttl
    }
  }

  # =============================================================================
  # SSL/TLS Configuration
  # =============================================================================
  viewer_certificate {
    # カスタムドメインがある場合はACM証明書を使用
    acm_certificate_arn            = var.acm_certificate_arn
    cloudfront_default_certificate = var.acm_certificate_arn == null ? true : false
    minimum_protocol_version       = var.minimum_protocol_version
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
  }

  # =============================================================================
  # Restrictions
  # =============================================================================
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-distribution"
  })
}
