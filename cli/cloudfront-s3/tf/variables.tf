# =============================================================================
# General Variables
# =============================================================================

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名（リソース名のプレフィックスに使用）"
  type        = string
  default     = "cloudfront-s3"
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
  default     = "dev"
}

variable "stack_name" {
  description = "スタック名（リソースのグループ識別用）"
  type        = string
}

# =============================================================================
# S3 Variables
# =============================================================================

variable "s3_bucket_name" {
  description = "S3バケット名（nullの場合は自動生成）"
  type        = string
  default     = null
}

variable "index_document" {
  description = "インデックスドキュメント"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "エラードキュメント"
  type        = string
  default     = "error.html"
}

variable "enable_versioning" {
  description = "S3バージョニングを有効にするか"
  type        = bool
  default     = false
}

# =============================================================================
# CloudFront Variables
# =============================================================================

variable "price_class" {
  description = "CloudFront価格クラス（PriceClass_100: 北米・欧州のみ, PriceClass_200: +アジア, PriceClass_All: 全エッジロケーション）"
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All"
  }
}

variable "default_ttl" {
  description = "デフォルトTTL（秒）"
  type        = number
  default     = 86400 # 1 day
}

variable "max_ttl" {
  description = "最大TTL（秒）"
  type        = number
  default     = 31536000 # 1 year
}

variable "min_ttl" {
  description = "最小TTL（秒）"
  type        = number
  default     = 0
}

variable "compress" {
  description = "コンテンツ圧縮を有効にするか"
  type        = bool
  default     = true
}

variable "viewer_protocol_policy" {
  description = "ビューワープロトコルポリシー（allow-all, https-only, redirect-to-https）"
  type        = string
  default     = "redirect-to-https"

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be one of: allow-all, https-only, redirect-to-https"
  }
}

variable "minimum_protocol_version" {
  description = "最小TLSプロトコルバージョン"
  type        = string
  default     = "TLSv1.2_2021"
}

# =============================================================================
# Custom Domain Variables (Optional)
# =============================================================================

variable "domain_names" {
  description = "カスタムドメイン名（オプション）"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM証明書ARN（カスタムドメイン使用時に必要、us-east-1リージョンの証明書）"
  type        = string
  default     = null
}

# =============================================================================
# SPA Support Variables
# =============================================================================

variable "enable_spa_mode" {
  description = "SPA（Single Page Application）モードを有効にするか（404エラーをindex.htmlにリダイレクト）"
  type        = bool
  default     = true
}

variable "spa_error_caching_min_ttl" {
  description = "SPAモードでのエラーキャッシュ最小TTL（秒）"
  type        = number
  default     = 300
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "追加のタグ"
  type        = map(string)
  default     = {}
}
