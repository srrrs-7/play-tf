variable "name" {
  description = "Name of the Amplify app"
  type        = string
}

variable "description" {
  description = "Description of the Amplify app"
  type        = string
  default     = null
}

# リポジトリ設定
variable "repository" {
  description = "Repository URL for the Amplify app"
  type        = string
  default     = null
}

variable "access_token" {
  description = "Personal access token for third-party source control (GitHub)"
  type        = string
  default     = null
  sensitive   = true
}

variable "oauth_token" {
  description = "OAuth token for third-party source control"
  type        = string
  default     = null
  sensitive   = true
}

# ビルド設定
variable "build_spec" {
  description = "Build specification (build commands, artifacts) in YAML format"
  type        = string
  default     = null
}

variable "enable_auto_branch_creation" {
  description = "Enable automatic branch creation for the Amplify app"
  type        = bool
  default     = false
}

variable "enable_branch_auto_build" {
  description = "Enable auto-building of branches for the Amplify app"
  type        = bool
  default     = true
}

variable "enable_branch_auto_deletion" {
  description = "Automatically disconnect a branch when deleted from the repository"
  type        = bool
  default     = false
}

variable "enable_basic_auth" {
  description = "Enable basic authentication for the Amplify app branches"
  type        = bool
  default     = false
}

variable "basic_auth_credentials" {
  description = "Basic auth credentials (base64 encoded username:password)"
  type        = string
  default     = null
  sensitive   = true
}

# 環境変数
variable "environment_variables" {
  description = "Environment variables for the Amplify app"
  type        = map(string)
  default     = {}
}

# IAM
variable "iam_service_role_arn" {
  description = "IAM service role ARN for the Amplify app"
  type        = string
  default     = null
}

# プラットフォーム
variable "platform" {
  description = "Platform for the Amplify app. Valid values: WEB, WEB_COMPUTE, WEB_DYNAMIC"
  type        = string
  default     = "WEB"

  validation {
    condition     = contains(["WEB", "WEB_COMPUTE", "WEB_DYNAMIC"], var.platform)
    error_message = "platform must be WEB, WEB_COMPUTE, or WEB_DYNAMIC."
  }
}

# 自動ブランチ作成設定
variable "auto_branch_creation_config" {
  description = "Configuration for auto branch creation"
  type = object({
    basic_auth_credentials        = optional(string)
    build_spec                    = optional(string)
    enable_auto_build             = optional(bool)
    enable_basic_auth             = optional(bool)
    enable_performance_mode       = optional(bool)
    enable_pull_request_preview   = optional(bool)
    environment_variables         = optional(map(string))
    framework                     = optional(string)
    pull_request_environment_name = optional(string)
    stage                         = optional(string)
  })
  default = null
}

variable "auto_branch_creation_patterns" {
  description = "Patterns for auto branch creation"
  type        = list(string)
  default     = []
}

# カスタムルール
variable "custom_rules" {
  description = "Custom redirect and rewrite rules"
  type = list(object({
    source    = string
    target    = string
    status    = optional(string)
    condition = optional(string)
  }))
  default = []
}

# ブランチ設定
variable "branches" {
  description = "List of branches to create"
  type = list(object({
    branch_name                   = string
    description                   = optional(string)
    display_name                  = optional(string)
    enable_auto_build             = optional(bool)
    enable_basic_auth             = optional(bool)
    basic_auth_credentials        = optional(string)
    enable_notification           = optional(bool)
    enable_performance_mode       = optional(bool)
    enable_pull_request_preview   = optional(bool)
    environment_variables         = optional(map(string))
    framework                     = optional(string)
    pull_request_environment_name = optional(string)
    stage                         = optional(string)
    ttl                           = optional(string)
    backend_environment_arn       = optional(string)
  }))
  default = []
}

# ドメイン設定
variable "domain_associations" {
  description = "List of domain associations"
  type = list(object({
    domain_name            = string
    enable_auto_sub_domain = optional(bool)
    wait_for_verification  = optional(bool)
    sub_domains = list(object({
      branch_name = string
      prefix      = string
    }))
  }))
  default = []
}

# Webhook設定
variable "webhooks" {
  description = "List of webhooks"
  type = list(object({
    branch_name = string
    description = optional(string)
  }))
  default = []
}

# バックエンド環境
variable "backend_environments" {
  description = "List of backend environments"
  type = list(object({
    environment_name     = string
    deployment_artifacts = optional(string)
    stack_name           = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
