variable "application_name" {
  description = "Elastic Beanstalkアプリケーション名"
  type        = string
}

variable "application_description" {
  description = "アプリケーションの説明"
  type        = string
  default     = ""
}

variable "environment_name" {
  description = "環境名"
  type        = string
}

variable "solution_stack_name" {
  description = "ソリューションスタック名"
  type        = string
}

variable "tier" {
  description = "環境ティア (WebServer, Worker)"
  type        = string
  default     = "WebServer"
}

variable "cname_prefix" {
  description = "CNAMEプレフィックス"
  type        = string
  default     = null
}

variable "version_label" {
  description = "アプリケーションバージョンラベル"
  type        = string
  default     = null
}

variable "appversion_lifecycle" {
  description = "アプリケーションバージョンライフサイクル設定"
  type = object({
    service_role          = string
    max_count             = optional(number)
    max_age_in_days       = optional(number)
    delete_source_from_s3 = optional(bool)
  })
  default = null
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "インスタンス用サブネットIDリスト"
  type        = list(string)
  default     = []
}

variable "elb_subnet_ids" {
  description = "ELB用サブネットIDリスト"
  type        = list(string)
  default     = []
}

variable "associate_public_ip_address" {
  description = "パブリックIPを関連付けるか"
  type        = bool
  default     = null
}

# Instance Configuration
variable "instance_type" {
  description = "EC2インスタンスタイプ"
  type        = string
  default     = "t3.micro"
}

variable "create_instance_profile" {
  description = "インスタンスプロファイルを作成するか"
  type        = bool
  default     = true
}

variable "instance_profile" {
  description = "既存のインスタンスプロファイル名"
  type        = string
  default     = null
}

variable "instance_additional_policies" {
  description = "インスタンスロールに追加するIAMポリシーARNリスト"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "セキュリティグループIDリスト"
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "EC2キーペア名"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "ルートボリュームサイズ (GB)"
  type        = number
  default     = null
}

variable "root_volume_type" {
  description = "ルートボリュームタイプ"
  type        = string
  default     = null
}

# Auto Scaling
variable "min_instances" {
  description = "最小インスタンス数"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "最大インスタンス数"
  type        = number
  default     = 4
}

# Environment Type
variable "environment_type" {
  description = "環境タイプ (LoadBalanced, SingleInstance)"
  type        = string
  default     = "LoadBalanced"
}

variable "load_balancer_type" {
  description = "ロードバランサータイプ (classic, application, network)"
  type        = string
  default     = "application"
}

# Service Role
variable "create_service_role" {
  description = "サービスロールを作成するか"
  type        = bool
  default     = true
}

variable "service_role" {
  description = "既存のサービスロールARN"
  type        = string
  default     = null
}

# Health Check
variable "health_check_url" {
  description = "ヘルスチェックURL"
  type        = string
  default     = null
}

variable "enhanced_reporting_enabled" {
  description = "拡張ヘルスレポートを有効にするか"
  type        = bool
  default     = true
}

# Managed Updates
variable "managed_updates_enabled" {
  description = "マネージド更新を有効にするか"
  type        = bool
  default     = false
}

variable "preferred_update_start_time" {
  description = "更新開始時間 (UTC)"
  type        = string
  default     = "Sun:10:00"
}

variable "update_level" {
  description = "更新レベル (patch, minor)"
  type        = string
  default     = "minor"
}

# CloudWatch Logs
variable "cloudwatch_logs_enabled" {
  description = "CloudWatch Logsを有効にするか"
  type        = bool
  default     = false
}

variable "cloudwatch_logs_retention_days" {
  description = "ログ保持日数"
  type        = number
  default     = 7
}

# Environment Variables
variable "environment_variables" {
  description = "環境変数"
  type        = map(string)
  default     = {}
}

# Additional Settings
variable "additional_settings" {
  description = "追加の設定"
  type = list(object({
    namespace = string
    name      = string
    value     = string
    resource  = optional(string)
  }))
  default = []
}

# Application Version
variable "create_application_version" {
  description = "アプリケーションバージョンを作成するか"
  type        = bool
  default     = false
}

variable "application_version_name" {
  description = "アプリケーションバージョン名"
  type        = string
  default     = null
}

variable "application_version_description" {
  description = "アプリケーションバージョンの説明"
  type        = string
  default     = null
}

variable "application_version_bucket" {
  description = "アプリケーションソースのS3バケット"
  type        = string
  default     = null
}

variable "application_version_key" {
  description = "アプリケーションソースのS3キー"
  type        = string
  default     = null
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
