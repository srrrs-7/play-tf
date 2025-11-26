variable "cluster_identifier" {
  description = "Auroraクラスター識別子"
  type        = string
}

variable "engine" {
  description = "データベースエンジン (aurora-mysql, aurora-postgresql)"
  type        = string
  default     = "aurora-mysql"
}

variable "engine_mode" {
  description = "エンジンモード (provisioned, serverless)"
  type        = string
  default     = "provisioned"
}

variable "engine_version" {
  description = "エンジンバージョン"
  type        = string
  default     = null
}

variable "database_name" {
  description = "初期データベース名"
  type        = string
  default     = null
}

variable "master_username" {
  description = "マスターユーザー名"
  type        = string
}

variable "master_password" {
  description = "マスターパスワード"
  type        = string
  sensitive   = true
}

variable "port" {
  description = "データベースポート"
  type        = number
  default     = null
}

variable "network_type" {
  description = "ネットワークタイプ (IPV4, DUAL)"
  type        = string
  default     = "IPV4"
}

variable "db_cluster_instance_class" {
  description = "クラスターインスタンスクラス (Multi-AZ用)"
  type        = string
  default     = null
}

variable "storage_type" {
  description = "ストレージタイプ"
  type        = string
  default     = null
}

variable "allocated_storage" {
  description = "割り当てストレージ (GB)"
  type        = number
  default     = null
}

variable "iops" {
  description = "プロビジョンドIOPS"
  type        = number
  default     = null
}

variable "instance_count" {
  description = "クラスターインスタンス数"
  type        = number
  default     = 2
}

variable "instance_class" {
  description = "インスタンスクラス"
  type        = string
  default     = "db.serverless"
}

variable "serverlessv2_scaling_configuration" {
  description = "Serverless v2スケーリング設定"
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = null
}

variable "scaling_configuration" {
  description = "Serverless v1スケーリング設定"
  type = object({
    auto_pause               = optional(bool)
    min_capacity             = optional(number)
    max_capacity             = optional(number)
    seconds_until_auto_pause = optional(number)
    timeout_action           = optional(string)
  })
  default = null
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "サブネットIDリスト"
  type        = list(string)
  default     = []
}

variable "create_db_subnet_group" {
  description = "DBサブネットグループを作成するか"
  type        = bool
  default     = true
}

variable "db_subnet_group_name" {
  description = "既存のDBサブネットグループ名"
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "VPCセキュリティグループIDリスト"
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  description = "セキュリティグループを作成するか"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "許可するCIDRブロック"
  type        = list(string)
  default     = []
}

variable "allowed_security_groups" {
  description = "許可するセキュリティグループID"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "パブリックアクセス可能か"
  type        = bool
  default     = false
}

variable "ca_cert_identifier" {
  description = "CA証明書識別子"
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "バックアップ保持期間（日）"
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "バックアップウィンドウ"
  type        = string
  default     = "02:00-03:00"
}

variable "preferred_maintenance_window" {
  description = "メンテナンスウィンドウ"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "skip_final_snapshot" {
  description = "最終スナップショットをスキップするか"
  type        = bool
  default     = false
}

variable "copy_tags_to_snapshot" {
  description = "スナップショットにタグをコピーするか"
  type        = bool
  default     = true
}

variable "storage_encrypted" {
  description = "ストレージ暗号化を有効にするか"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "暗号化用KMSキーID"
  type        = string
  default     = null
}

variable "iam_database_authentication_enabled" {
  description = "IAMデータベース認証を有効にするか"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "削除保護を有効にするか"
  type        = bool
  default     = false
}

variable "enabled_cloudwatch_logs_exports" {
  description = "CloudWatch Logsにエクスポートするログタイプ"
  type        = list(string)
  default     = []
}

variable "create_cluster_parameter_group" {
  description = "クラスターパラメータグループを作成するか"
  type        = bool
  default     = false
}

variable "db_cluster_parameter_group_name" {
  description = "既存のクラスターパラメータグループ名"
  type        = string
  default     = null
}

variable "create_db_parameter_group" {
  description = "DBパラメータグループを作成するか"
  type        = bool
  default     = false
}

variable "db_parameter_group_name" {
  description = "既存のDBパラメータグループ名"
  type        = string
  default     = null
}

variable "parameter_group_family" {
  description = "パラメータグループファミリー"
  type        = string
  default     = "aurora-mysql8.0"
}

variable "cluster_parameters" {
  description = "クラスターパラメータ"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string)
  }))
  default = []
}

variable "db_parameters" {
  description = "DBインスタンスパラメータ"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string)
  }))
  default = []
}

variable "performance_insights_enabled" {
  description = "Performance Insightsを有効にするか"
  type        = bool
  default     = false
}

variable "performance_insights_kms_key_id" {
  description = "Performance Insights用KMSキーID"
  type        = string
  default     = null
}

variable "performance_insights_retention_period" {
  description = "Performance Insightsデータ保持期間（日）"
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "拡張モニタリング間隔（秒）"
  type        = number
  default     = 0
}

variable "monitoring_role_arn" {
  description = "拡張モニタリング用IAMロールARN"
  type        = string
  default     = null
}

variable "create_monitoring_role" {
  description = "モニタリング用IAMロールを作成するか"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "マイナーバージョン自動アップグレードを有効にするか"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "変更を即座に適用するか"
  type        = bool
  default     = false
}

variable "create_cloudwatch_alarms" {
  description = "CloudWatchアラームを作成するか"
  type        = bool
  default     = false
}

variable "cpu_alarm_threshold" {
  description = "CPU使用率アラーム閾値（%）"
  type        = number
  default     = 80
}

variable "memory_alarm_threshold" {
  description = "空きメモリアラーム閾値（バイト）"
  type        = number
  default     = 1000000000
}

variable "alarm_actions" {
  description = "アラームアクションARNリスト"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "OKアクションARNリスト"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
