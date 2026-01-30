# =============================================================================
# 基本設定
# =============================================================================

variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境名 (dev, stg, prd)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

# =============================================================================
# S3 設定
# =============================================================================

variable "enable_s3_versioning" {
  description = "S3バージョニングを有効にするか"
  type        = bool
  default     = true
}

variable "s3_lifecycle_rules" {
  description = "S3ライフサイクルルール"
  type = list(object({
    id                                 = string
    enabled                            = bool
    prefix                             = optional(string)
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []
}

# =============================================================================
# Cognito 設定
# =============================================================================

variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI ドメインプレフィックス"
  type        = string
}

variable "mfa_configuration" {
  description = "MFA設定 (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OFF"
}

variable "password_policy" {
  description = "パスワードポリシー"
  type = object({
    minimum_length                   = optional(number, 8)
    require_lowercase                = optional(bool, true)
    require_uppercase                = optional(bool, true)
    require_numbers                  = optional(bool, true)
    require_symbols                  = optional(bool, false)
    temporary_password_validity_days = optional(number, 7)
  })
  default = {}
}

variable "cognito_callback_urls" {
  description = "Cognito コールバックURL"
  type        = list(string)
  default     = ["https://localhost/auth/callback"]
}

variable "cognito_logout_urls" {
  description = "Cognito ログアウトURL"
  type        = list(string)
  default     = ["https://localhost/"]
}

variable "access_token_validity_hours" {
  description = "アクセストークン有効期間（時間）"
  type        = number
  default     = 1
}

variable "id_token_validity_hours" {
  description = "IDトークン有効期間（時間）"
  type        = number
  default     = 1
}

variable "refresh_token_validity_days" {
  description = "リフレッシュトークン有効期間（日）"
  type        = number
  default     = 30
}

# =============================================================================
# CloudFront 設定
# =============================================================================

variable "default_root_object" {
  description = "デフォルトルートオブジェクト"
  type        = string
  default     = "index.html"
}

variable "cloudfront_price_class" {
  description = "CloudFront価格クラス"
  type        = string
  default     = "PriceClass_200"
}

variable "geo_restriction_type" {
  description = "地理的制限タイプ (none, whitelist, blacklist)"
  type        = string
  default     = "none"
}

variable "geo_restriction_locations" {
  description = "地理的制限対象の国コード"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM証明書ARN（カスタムドメイン使用時）"
  type        = string
  default     = null
}

variable "domain_aliases" {
  description = "カスタムドメイン名"
  type        = list(string)
  default     = []
}

# =============================================================================
# ログ設定
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch Logs保持期間（日）"
  type        = number
  default     = 30
}
