variable "api_name" {
  description = "API Gateway の名前"
  type        = string
}

variable "description" {
  description = "API Gateway の説明"
  type        = string
  default     = ""
}

variable "stage_name" {
  description = "ステージ名 (e.g., dev, stg, prod)"
  type        = string
  default     = "dev"
}

variable "endpoint_types" {
  description = "エンドポイントタイプ"
  type        = list(string)
  default     = ["REGIONAL"]

  validation {
    condition     = alltrue([for type in var.endpoint_types : contains(["EDGE", "REGIONAL", "PRIVATE"], type)])
    error_message = "Endpoint types must be one of: EDGE, REGIONAL, PRIVATE."
  }
}

variable "lambda_invoke_arn" {
  description = "Lambda関数のInvoke ARN"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda関数名"
  type        = string
}

variable "authorization_type" {
  description = "認証タイプ (NONE, AWS_IAM, CUSTOM, COGNITO_USER_POOLS)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM", "CUSTOM", "COGNITO_USER_POOLS"], var.authorization_type)
    error_message = "Authorization type must be one of: NONE, AWS_IAM, CUSTOM, COGNITO_USER_POOLS."
  }
}

variable "authorizer_id" {
  description = "Lambda Authorizer ID (CUSTOM認証の場合)"
  type        = string
  default     = null
}

variable "xray_tracing_enabled" {
  description = "X-Rayトレーシングを有効にするか"
  type        = bool
  default     = false
}

variable "cache_cluster_size" {
  description = "キャッシュクラスタのサイズ (0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237)"
  type        = string
  default     = null

  validation {
    condition     = var.cache_cluster_size == null || contains(["0.5", "1.6", "6.1", "13.5", "28.4", "58.2", "118", "237"], var.cache_cluster_size)
    error_message = "Cache cluster size must be one of: 0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237."
  }
}

variable "stage_variables" {
  description = "ステージ変数"
  type        = map(string)
  default     = {}
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

variable "log_destination_arn" {
  description = "ログ出力先のARN（指定しない場合は自動作成）"
  type        = string
  default     = null
}

variable "enable_cors" {
  description = "CORSを有効にするか"
  type        = bool
  default     = false
}

variable "cors_allow_origin" {
  description = "CORS Allow-Origin ヘッダーの値"
  type        = string
  default     = "'*'"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
