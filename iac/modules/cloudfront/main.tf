# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = var.enabled
  is_ipv6_enabled     = var.is_ipv6_enabled
  comment             = var.comment
  default_root_object = var.default_root_object
  price_class         = var.price_class
  aliases             = var.aliases
  web_acl_id          = var.web_acl_id

  # Origin configuration
  dynamic "origin" {
    for_each = var.origins
    content {
      domain_name              = origin.value.domain_name
      origin_id                = origin.value.origin_id
      origin_path              = lookup(origin.value, "origin_path", null)
      connection_attempts      = lookup(origin.value, "connection_attempts", 3)
      connection_timeout       = lookup(origin.value, "connection_timeout", 10)
      origin_access_control_id = lookup(origin.value, "origin_access_control_id", null)

      dynamic "custom_origin_config" {
        for_each = lookup(origin.value, "custom_origin_config", null) != null ? [origin.value.custom_origin_config] : []
        content {
          http_port                = lookup(custom_origin_config.value, "http_port", 80)
          https_port               = lookup(custom_origin_config.value, "https_port", 443)
          origin_protocol_policy   = lookup(custom_origin_config.value, "origin_protocol_policy", "https-only")
          origin_ssl_protocols     = lookup(custom_origin_config.value, "origin_ssl_protocols", ["TLSv1.2"])
          origin_keepalive_timeout = lookup(custom_origin_config.value, "origin_keepalive_timeout", 5)
          origin_read_timeout      = lookup(custom_origin_config.value, "origin_read_timeout", 30)
        }
      }

      dynamic "s3_origin_config" {
        for_each = lookup(origin.value, "s3_origin_config", null) != null ? [origin.value.s3_origin_config] : []
        content {
          origin_access_identity = s3_origin_config.value.origin_access_identity
        }
      }

      dynamic "custom_header" {
        for_each = lookup(origin.value, "custom_headers", [])
        content {
          name  = custom_header.value.name
          value = custom_header.value.value
        }
      }
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods  = var.default_cache_behavior.allowed_methods
    cached_methods   = var.default_cache_behavior.cached_methods
    target_origin_id = var.default_cache_behavior.target_origin_id
    compress         = lookup(var.default_cache_behavior, "compress", true)

    viewer_protocol_policy = lookup(var.default_cache_behavior, "viewer_protocol_policy", "redirect-to-https")
    min_ttl                = lookup(var.default_cache_behavior, "min_ttl", 0)
    default_ttl            = lookup(var.default_cache_behavior, "default_ttl", 86400)
    max_ttl                = lookup(var.default_cache_behavior, "max_ttl", 31536000)

    # Use cache policy if specified, otherwise use legacy forwarded_values
    cache_policy_id            = lookup(var.default_cache_behavior, "cache_policy_id", null)
    origin_request_policy_id   = lookup(var.default_cache_behavior, "origin_request_policy_id", null)
    response_headers_policy_id = lookup(var.default_cache_behavior, "response_headers_policy_id", null)

    dynamic "forwarded_values" {
      for_each = lookup(var.default_cache_behavior, "cache_policy_id", null) == null ? [1] : []
      content {
        query_string = lookup(var.default_cache_behavior, "forward_query_string", true)
        headers      = lookup(var.default_cache_behavior, "forward_headers", [])

        cookies {
          forward           = lookup(var.default_cache_behavior, "forward_cookies", "none")
          whitelisted_names = lookup(var.default_cache_behavior, "forward_cookies_whitelist", null)
        }
      }
    }

    dynamic "function_association" {
      for_each = lookup(var.default_cache_behavior, "function_associations", [])
      content {
        event_type   = function_association.value.event_type
        function_arn = function_association.value.function_arn
      }
    }

    dynamic "lambda_function_association" {
      for_each = lookup(var.default_cache_behavior, "lambda_function_associations", [])
      content {
        event_type   = lambda_function_association.value.event_type
        lambda_arn   = lambda_function_association.value.lambda_arn
        include_body = lookup(lambda_function_association.value, "include_body", false)
      }
    }
  }

  # Additional cache behaviors
  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors
    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ordered_cache_behavior.value.allowed_methods
      cached_methods   = ordered_cache_behavior.value.cached_methods
      target_origin_id = ordered_cache_behavior.value.target_origin_id
      compress         = lookup(ordered_cache_behavior.value, "compress", true)

      viewer_protocol_policy = lookup(ordered_cache_behavior.value, "viewer_protocol_policy", "redirect-to-https")
      min_ttl                = lookup(ordered_cache_behavior.value, "min_ttl", 0)
      default_ttl            = lookup(ordered_cache_behavior.value, "default_ttl", 86400)
      max_ttl                = lookup(ordered_cache_behavior.value, "max_ttl", 31536000)

      cache_policy_id            = lookup(ordered_cache_behavior.value, "cache_policy_id", null)
      origin_request_policy_id   = lookup(ordered_cache_behavior.value, "origin_request_policy_id", null)
      response_headers_policy_id = lookup(ordered_cache_behavior.value, "response_headers_policy_id", null)

      dynamic "forwarded_values" {
        for_each = lookup(ordered_cache_behavior.value, "cache_policy_id", null) == null ? [1] : []
        content {
          query_string = lookup(ordered_cache_behavior.value, "forward_query_string", true)
          headers      = lookup(ordered_cache_behavior.value, "forward_headers", [])

          cookies {
            forward           = lookup(ordered_cache_behavior.value, "forward_cookies", "none")
            whitelisted_names = lookup(ordered_cache_behavior.value, "forward_cookies_whitelist", null)
          }
        }
      }

      dynamic "function_association" {
        for_each = lookup(ordered_cache_behavior.value, "function_associations", [])
        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.function_arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = lookup(ordered_cache_behavior.value, "lambda_function_associations", [])
        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.lambda_arn
          include_body = lookup(lambda_function_association.value, "include_body", false)
        }
      }
    }
  }

  # Custom error responses
  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = lookup(custom_error_response.value, "response_code", null)
      response_page_path    = lookup(custom_error_response.value, "response_page_path", null)
      error_caching_min_ttl = lookup(custom_error_response.value, "error_caching_min_ttl", null)
    }
  }

  # Restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.restriction_type
      locations        = var.geo_restriction.locations
    }
  }

  # SSL/TLS certificate
  viewer_certificate {
    cloudfront_default_certificate = var.viewer_certificate.cloudfront_default_certificate
    acm_certificate_arn            = lookup(var.viewer_certificate, "acm_certificate_arn", null)
    iam_certificate_id             = lookup(var.viewer_certificate, "iam_certificate_id", null)
    minimum_protocol_version       = lookup(var.viewer_certificate, "minimum_protocol_version", "TLSv1.2_2021")
    ssl_support_method             = lookup(var.viewer_certificate, "ssl_support_method", "sni-only")
  }

  # Logging configuration
  dynamic "logging_config" {
    for_each = var.logging_config != null ? [var.logging_config] : []
    content {
      bucket          = logging_config.value.bucket
      prefix          = lookup(logging_config.value, "prefix", "")
      include_cookies = lookup(logging_config.value, "include_cookies", false)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.distribution_name
    }
  )
}

# Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "main" {
  count = var.create_origin_access_control ? 1 : 0

  name                              = var.origin_access_control_name
  description                       = var.origin_access_control_description
  origin_access_control_origin_type = var.origin_access_control_origin_type
  signing_behavior                  = var.origin_access_control_signing_behavior
  signing_protocol                  = var.origin_access_control_signing_protocol
}

# CloudFront Function
resource "aws_cloudfront_function" "main" {
  for_each = var.cloudfront_functions

  name    = each.value.name
  runtime = lookup(each.value, "runtime", "cloudfront-js-1.0")
  comment = lookup(each.value, "comment", null)
  publish = lookup(each.value, "publish", true)
  code    = each.value.code
}
