variable "function_name" {
  description = "Lambda関数名"
  type        = string
}

variable "description" {
  description = "Lambda関数の説明"
  type        = string
  default     = ""
}

variable "runtime" {
  description = "ランタイム (e.g., python3.11, nodejs20.x, go1.x)"
  type        = string
}

variable "handler" {
  description = "ハンドラー (e.g., index.handler, main)"
  type        = string
}

variable "source_path" {
  description = "ソースコードのパス（ファイルまたはディレクトリ）"
  type        = string
}

variable "timeout" {
  description = "タイムアウト秒数"
  type        = number
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "Timeout must be between 1 and 900 seconds."
  }
}

variable "memory_size" {
  description = "メモリサイズ (MB)"
  type        = number
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "Memory size must be between 128 and 10240 MB."
  }
}

variable "environment_variables" {
  description = "環境変数"
  type        = map(string)
  default     = {}
}

variable "vpc_config" {
  description = "VPC設定"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "layers" {
  description = "Lambda Layerのリスト"
  type        = list(string)
  default     = []
}

variable "reserved_concurrent_executions" {
  description = "予約済み同時実行数 (-1で無制限)"
  type        = number
  default     = -1
}

variable "architectures" {
  description = "アーキテクチャ ([\"x86_64\"] or [\"arm64\"])"
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition     = alltrue([for arch in var.architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "Architectures must be either x86_64 or arm64."
  }
}

variable "create_log_group" {
  description = "CloudWatch Logs グループを作成するか"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "ログ保持期間（日数）"
  type        = number
  default     = 7
}

variable "policy_statements" {
  description = "Lambda実行ロールに追加するIAMポリシーステートメント"
  type = list(object({
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
