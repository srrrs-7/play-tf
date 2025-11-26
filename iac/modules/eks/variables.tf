variable "cluster_name" {
  description = "EKSクラスター名"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetesバージョン"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "EKSクラスター用サブネットIDリスト"
  type        = list(string)
}

variable "create_cluster_role" {
  description = "クラスターIAMロールを作成するか"
  type        = bool
  default     = true
}

variable "cluster_role_arn" {
  description = "既存のクラスターIAMロールARN"
  type        = string
  default     = null
}

variable "endpoint_private_access" {
  description = "プライベートエンドポイントアクセスを有効にするか"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "パブリックエンドポイントアクセスを有効にするか"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "パブリックアクセスを許可するCIDRリスト"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_security_group_ids" {
  description = "クラスターに関連付ける追加のセキュリティグループID"
  type        = list(string)
  default     = []
}

variable "cluster_encryption_config" {
  description = "クラスター暗号化設定"
  type = object({
    provider_key_arn = string
    resources        = list(string)
  })
  default = null
}

variable "enabled_cluster_log_types" {
  description = "有効にするクラスターログタイプ"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_in_days" {
  description = "クラスターログの保持日数"
  type        = number
  default     = 7
}

variable "cluster_log_kms_key_id" {
  description = "クラスターログ暗号化用KMSキーID"
  type        = string
  default     = null
}

variable "kubernetes_network_config" {
  description = "Kubernetesネットワーク設定"
  type = object({
    service_ipv4_cidr = optional(string)
    ip_family         = optional(string)
  })
  default = null
}

variable "node_groups" {
  description = "マネージドノードグループ設定"
  type = map(object({
    name           = string
    instance_types = optional(list(string))
    capacity_type  = optional(string)
    disk_size      = optional(number)
    ami_type       = optional(string)
    desired_size   = optional(number)
    min_size       = optional(number)
    max_size       = optional(number)
    subnet_ids     = optional(list(string))
    labels         = optional(map(string))
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })))
    update_config = optional(object({
      max_unavailable            = optional(number)
      max_unavailable_percentage = optional(number)
    }))
    launch_template = optional(object({
      id      = optional(string)
      name    = optional(string)
      version = string
    }))
    tags = optional(map(string))
  }))
  default = {}
}

variable "create_node_role" {
  description = "ノードIAMロールを作成するか"
  type        = bool
  default     = true
}

variable "node_role_arn" {
  description = "既存のノードIAMロールARN"
  type        = string
  default     = null
}

variable "node_additional_policies" {
  description = "ノードロールに追加するIAMポリシーARNリスト"
  type        = list(string)
  default     = []
}

variable "fargate_profiles" {
  description = "Fargateプロファイル設定"
  type = map(object({
    name       = string
    subnet_ids = optional(list(string))
    selectors = list(object({
      namespace = string
      labels    = optional(map(string))
    }))
    tags = optional(map(string))
  }))
  default = {}
}

variable "create_fargate_role" {
  description = "Fargate IAMロールを作成するか"
  type        = bool
  default     = true
}

variable "fargate_role_arn" {
  description = "既存のFargate IAMロールARN"
  type        = string
  default     = null
}

variable "cluster_addons" {
  description = "EKSアドオン設定"
  type = map(object({
    addon_version               = optional(string)
    resolve_conflicts_on_create = optional(string)
    resolve_conflicts_on_update = optional(string)
    service_account_role_arn    = optional(string)
    configuration_values        = optional(string)
  }))
  default = {}
}

variable "enable_irsa" {
  description = "IAM Roles for Service Accounts (IRSA)を有効にするか"
  type        = bool
  default     = true
}

variable "create_cluster_security_group" {
  description = "追加のクラスターセキュリティグループを作成するか"
  type        = bool
  default     = false
}

variable "cluster_security_group_additional_rules" {
  description = "クラスターセキュリティグループの追加ルール"
  type = map(object({
    type                     = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = optional(list(string))
    source_security_group_id = optional(string)
    description              = optional(string)
  }))
  default = {}
}

variable "create_node_security_group" {
  description = "追加のノードセキュリティグループを作成するか"
  type        = bool
  default     = false
}

variable "node_security_group_additional_rules" {
  description = "ノードセキュリティグループの追加ルール"
  type = map(object({
    type                     = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = optional(list(string))
    source_security_group_id = optional(string)
    description              = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
