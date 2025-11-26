variable "distribution_name" {
  description = "CloudFrontディストリビューション名"
  type        = string
}

variable "enabled" {
  description = "ディストリビューションを有効化するか"
  type        = bool
  default     = true
}

variable "is_ipv6_enabled" {
  description = "IPv6を有効化するか"
  type        = bool
  default     = true
}

variable "comment" {
  description = "ディストリビューションのコメント"
  type        = string
  default     = ""
}

variable "default_root_object" {
  description = "デフォルトルートオブジェクト"
  type        = string
  default     = null
}

variable "price_class" {
  description = "価格クラス (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_200"
}

variable "aliases" {
  description = "カスタムドメイン名のリスト"
  type        = list(string)
  default     = []
}

variable "web_acl_id" {
  description = "WAF Web ACL ID"
  type        = string
  default     = null
}

variable "origins" {
  description = "オリジン設定のリスト"
  type = list(object({
    domain_name              = string
    origin_id                = string
    origin_path              = optional(string)
    connection_attempts      = optional(number)
    connection_timeout       = optional(number)
    origin_access_control_id = optional(string)
    custom_origin_config = optional(object({
      http_port                = optional(number)
      https_port               = optional(number)
      origin_protocol_policy   = optional(string)
      origin_ssl_protocols     = optional(list(string))
      origin_keepalive_timeout = optional(number)
      origin_read_timeout      = optional(number)
    }))
    s3_origin_config = optional(object({
      origin_access_identity = string
    }))
    custom_headers = optional(list(object({
      name  = string
      value = string
    })))
  }))
}

variable "default_cache_behavior" {
  description = "デフォルトキャッシュビヘイビア設定"
  type = object({
    allowed_methods            = list(string)
    cached_methods             = list(string)
    target_origin_id           = string
    compress                   = optional(bool)
    viewer_protocol_policy     = optional(string)
    min_ttl                    = optional(number)
    default_ttl                = optional(number)
    max_ttl                    = optional(number)
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    forward_query_string       = optional(bool)
    forward_headers            = optional(list(string))
    forward_cookies            = optional(string)
    forward_cookies_whitelist  = optional(list(string))
    function_associations = optional(list(object({
      event_type   = string
      function_arn = string
    })))
    lambda_function_associations = optional(list(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool)
    })))
  })
}

variable "ordered_cache_behaviors" {
  description = "追加のキャッシュビヘイビア設定"
  type = list(object({
    path_pattern               = string
    allowed_methods            = list(string)
    cached_methods             = list(string)
    target_origin_id           = string
    compress                   = optional(bool)
    viewer_protocol_policy     = optional(string)
    min_ttl                    = optional(number)
    default_ttl                = optional(number)
    max_ttl                    = optional(number)
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    forward_query_string       = optional(bool)
    forward_headers            = optional(list(string))
    forward_cookies            = optional(string)
    forward_cookies_whitelist  = optional(list(string))
    function_associations = optional(list(object({
      event_type   = string
      function_arn = string
    })))
    lambda_function_associations = optional(list(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool)
    })))
  }))
  default = []
}

variable "custom_error_responses" {
  description = "カスタムエラーレスポンス設定"
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
  default = []
}

variable "geo_restriction" {
  description = "地理的制限設定"
  type = object({
    restriction_type = string
    locations        = list(string)
  })
  default = {
    restriction_type = "none"
    locations        = []
  }
}

variable "viewer_certificate" {
  description = "SSL/TLS証明書設定"
  type = object({
    cloudfront_default_certificate = bool
    acm_certificate_arn            = optional(string)
    iam_certificate_id             = optional(string)
    minimum_protocol_version       = optional(string)
    ssl_support_method             = optional(string)
  })
  default = {
    cloudfront_default_certificate = true
  }
}

variable "logging_config" {
  description = "アクセスログ設定"
  type = object({
    bucket          = string
    prefix          = optional(string)
    include_cookies = optional(bool)
  })
  default = null
}

variable "create_origin_access_control" {
  description = "Origin Access Controlを作成するか"
  type        = bool
  default     = false
}

variable "origin_access_control_name" {
  description = "Origin Access Control名"
  type        = string
  default     = ""
}

variable "origin_access_control_description" {
  description = "Origin Access Controlの説明"
  type        = string
  default     = "Origin Access Control for S3"
}

variable "origin_access_control_origin_type" {
  description = "Origin Access Controlのオリジンタイプ"
  type        = string
  default     = "s3"
}

variable "origin_access_control_signing_behavior" {
  description = "Origin Access Controlの署名動作"
  type        = string
  default     = "always"
}

variable "origin_access_control_signing_protocol" {
  description = "Origin Access Controlの署名プロトコル"
  type        = string
  default     = "sigv4"
}

variable "cloudfront_functions" {
  description = "CloudFront Functions設定"
  type = map(object({
    name    = string
    runtime = optional(string)
    comment = optional(string)
    publish = optional(bool)
    code    = string
  }))
  default = {}
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
