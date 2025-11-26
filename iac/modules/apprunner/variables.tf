variable "service_name" {
  description = "App Runnerサービス名"
  type        = string
}

variable "source_type" {
  description = "ソースタイプ (ecr, code)"
  type        = string
  default     = "ecr"
  validation {
    condition     = contains(["ecr", "code"], var.source_type)
    error_message = "source_type must be 'ecr' or 'code'"
  }
}

variable "auto_deployments_enabled" {
  description = "自動デプロイを有効にするか"
  type        = bool
  default     = true
}

variable "image_repository" {
  description = "ECRイメージリポジトリ設定"
  type = object({
    image_identifier      = string
    image_repository_type = optional(string)
    image_configuration = object({
      port                          = optional(string)
      runtime_environment_variables = optional(map(string))
      runtime_environment_secrets   = optional(map(string))
      start_command                 = optional(string)
    })
  })
  default = null
}

variable "code_repository" {
  description = "コードリポジトリ設定"
  type = object({
    repository_url = string
    source_code_version = object({
      type  = optional(string)
      value = string
    })
    code_configuration = object({
      configuration_source = optional(string)
      code_configuration_values = optional(object({
        runtime                       = string
        build_command                 = optional(string)
        start_command                 = optional(string)
        port                          = optional(string)
        runtime_environment_variables = optional(map(string))
        runtime_environment_secrets   = optional(map(string))
      }))
    })
    source_directory = optional(string)
  })
  default = null
}

variable "authentication_configuration" {
  description = "認証設定"
  type = object({
    access_role_arn = optional(string)
    connection_arn  = optional(string)
  })
  default = null
}

variable "cpu" {
  description = "CPU設定 (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "1024"
}

variable "memory" {
  description = "メモリ設定 (512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288)"
  type        = string
  default     = "2048"
}

variable "create_instance_role" {
  description = "インスタンスIAMロールを作成するか"
  type        = bool
  default     = true
}

variable "instance_role_arn" {
  description = "既存のインスタンスIAMロールARN"
  type        = string
  default     = null
}

variable "instance_policy_statements" {
  description = "インスタンスロールに追加するポリシーステートメント"
  type        = list(any)
  default     = []
}

variable "instance_additional_policies" {
  description = "インスタンスロールに追加するマネージドポリシーARNリスト"
  type        = list(string)
  default     = []
}

variable "health_check_configuration" {
  description = "ヘルスチェック設定"
  type = object({
    protocol            = optional(string)
    path                = optional(string)
    interval            = optional(number)
    timeout             = optional(number)
    healthy_threshold   = optional(number)
    unhealthy_threshold = optional(number)
  })
  default = null
}

variable "network_configuration" {
  description = "ネットワーク設定"
  type = object({
    is_publicly_accessible = optional(bool)
    egress_configuration = optional(object({
      egress_type       = optional(string)
      vpc_connector_arn = optional(string)
    }))
    ip_address_type = optional(string)
  })
  default = null
}

variable "create_vpc_connector" {
  description = "VPCコネクタを作成するか"
  type        = bool
  default     = false
}

variable "vpc_connector_subnets" {
  description = "VPCコネクタ用サブネットIDリスト"
  type        = list(string)
  default     = []
}

variable "vpc_connector_security_groups" {
  description = "VPCコネクタ用セキュリティグループIDリスト"
  type        = list(string)
  default     = []
}

variable "create_auto_scaling_configuration" {
  description = "オートスケーリング設定を作成するか"
  type        = bool
  default     = true
}

variable "auto_scaling_configuration_arn" {
  description = "既存のオートスケーリング設定ARN"
  type        = string
  default     = null
}

variable "auto_scaling_max_concurrency" {
  description = "最大同時リクエスト数"
  type        = number
  default     = 100
}

variable "auto_scaling_max_size" {
  description = "最大インスタンス数"
  type        = number
  default     = 25
}

variable "auto_scaling_min_size" {
  description = "最小インスタンス数"
  type        = number
  default     = 1
}

variable "observability_configuration_arn" {
  description = "可観測性設定ARN"
  type        = string
  default     = null
}

variable "create_observability_configuration" {
  description = "可観測性設定を作成するか"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "暗号化用KMSキーARN"
  type        = string
  default     = null
}

variable "create_ecr_access_role" {
  description = "ECRアクセス用IAMロールを作成するか"
  type        = bool
  default     = true
}

variable "create_github_connection" {
  description = "GitHub接続を作成するか"
  type        = bool
  default     = false
}

variable "custom_domains" {
  description = "カスタムドメイン設定"
  type = map(object({
    domain_name          = string
    enable_www_subdomain = optional(bool)
  }))
  default = {}
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
