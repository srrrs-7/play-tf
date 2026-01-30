# =============================================================================
# User Pool 基本設定
# =============================================================================

variable "user_pool_name" {
  description = "Cognito User Pool名"
  type        = string
}

variable "username_attributes" {
  description = "ユーザー名として使用する属性 (email, phone_number)"
  type        = list(string)
  default     = ["email"]
}

variable "auto_verified_attributes" {
  description = "自動検証する属性"
  type        = list(string)
  default     = ["email"]
}

variable "mfa_configuration" {
  description = "MFA設定 (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "MFA configuration must be OFF, ON, or OPTIONAL."
  }
}

variable "allow_admin_create_user_only" {
  description = "管理者のみがユーザーを作成できるようにするか"
  type        = bool
  default     = false
}

# =============================================================================
# パスワードポリシー
# =============================================================================

variable "password_policy" {
  description = "パスワードポリシー設定"
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

# =============================================================================
# メール設定
# =============================================================================

variable "email_configuration" {
  description = "メール設定（SES使用時）"
  type = object({
    email_sending_account  = optional(string, "COGNITO_DEFAULT")
    source_arn             = optional(string)
    reply_to_email_address = optional(string)
    from_email_address     = optional(string)
  })
  default = null
}

variable "verification_email_option" {
  description = "検証メールオプション (CONFIRM_WITH_CODE, CONFIRM_WITH_LINK)"
  type        = string
  default     = "CONFIRM_WITH_CODE"
}

variable "invite_message_template" {
  description = "招待メッセージテンプレート"
  type = object({
    email_message = optional(string)
    email_subject = optional(string)
    sms_message   = optional(string)
  })
  default = null
}

# =============================================================================
# スキーマ属性
# =============================================================================

variable "schema_attributes" {
  description = "カスタムユーザー属性スキーマ"
  type = list(object({
    name                     = string
    attribute_data_type      = string
    mutable                  = optional(bool, true)
    required                 = optional(bool, false)
    developer_only_attribute = optional(bool, false)
    string_constraints = optional(object({
      min_length = optional(number)
      max_length = optional(number)
    }))
    number_constraints = optional(object({
      min_value = optional(number)
      max_value = optional(number)
    }))
  }))
  default = []
}

# =============================================================================
# Lambda トリガー
# =============================================================================

variable "lambda_config" {
  description = "Lambda トリガー設定"
  type = object({
    pre_sign_up                    = optional(string)
    pre_authentication             = optional(string)
    post_authentication            = optional(string)
    post_confirmation              = optional(string)
    pre_token_generation           = optional(string)
    user_migration                 = optional(string)
    custom_message                 = optional(string)
    define_auth_challenge          = optional(string)
    create_auth_challenge          = optional(string)
    verify_auth_challenge_response = optional(string)
  })
  default = null
}

# =============================================================================
# User Pool クライアント設定
# =============================================================================

variable "create_user_pool_client" {
  description = "User Pool クライアントを作成するか"
  type        = bool
  default     = true
}

variable "user_pool_client_name" {
  description = "User Pool クライアント名"
  type        = string
  default     = "app-client"
}

variable "generate_client_secret" {
  description = "クライアントシークレットを生成するか"
  type        = bool
  default     = true
}

variable "explicit_auth_flows" {
  description = "許可する認証フロー"
  type        = list(string)
  default     = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
}

variable "allowed_oauth_flows" {
  description = "許可するOAuthフロー"
  type        = list(string)
  default     = ["code"]
}

variable "allowed_oauth_flows_user_pool_client" {
  description = "OAuth フローを有効にするか"
  type        = bool
  default     = true
}

variable "allowed_oauth_scopes" {
  description = "許可するOAuthスコープ"
  type        = list(string)
  default     = ["openid", "email", "profile"]
}

variable "supported_identity_providers" {
  description = "サポートするIDプロバイダー"
  type        = list(string)
  default     = ["COGNITO"]
}

variable "callback_urls" {
  description = "コールバックURL"
  type        = list(string)
  default     = ["https://localhost/auth/callback"]
}

variable "logout_urls" {
  description = "ログアウトURL"
  type        = list(string)
  default     = ["https://localhost/"]
}

# =============================================================================
# トークン設定
# =============================================================================

variable "access_token_validity" {
  description = "アクセストークンの有効期間"
  type        = number
  default     = 1
}

variable "id_token_validity" {
  description = "IDトークンの有効期間"
  type        = number
  default     = 1
}

variable "refresh_token_validity" {
  description = "リフレッシュトークンの有効期間"
  type        = number
  default     = 30
}

variable "token_validity_units" {
  description = "トークン有効期間の単位"
  type = object({
    access_token  = optional(string, "hours")
    id_token      = optional(string, "hours")
    refresh_token = optional(string, "days")
  })
  default = {}
}

variable "prevent_user_existence_errors" {
  description = "ユーザー存在エラーを防ぐ (ENABLED, LEGACY)"
  type        = string
  default     = "ENABLED"
}

variable "read_attributes" {
  description = "読み取り可能な属性"
  type        = list(string)
  default     = null
}

variable "write_attributes" {
  description = "書き込み可能な属性"
  type        = list(string)
  default     = null
}

# =============================================================================
# User Pool ドメイン設定
# =============================================================================

variable "create_user_pool_domain" {
  description = "User Pool ドメインを作成するか"
  type        = bool
  default     = true
}

variable "user_pool_domain" {
  description = "User Pool ドメイン名（Cognito ホストUI用）"
  type        = string
  default     = null
}

variable "domain_certificate_arn" {
  description = "カスタムドメイン用ACM証明書ARN"
  type        = string
  default     = null
}

# =============================================================================
# リソースサーバー
# =============================================================================

variable "resource_servers" {
  description = "リソースサーバー設定（カスタムスコープ用）"
  type = map(object({
    identifier = string
    name       = string
    scopes = optional(list(object({
      scope_name        = string
      scope_description = string
    })), [])
  }))
  default = {}
}

# =============================================================================
# 共通
# =============================================================================

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
