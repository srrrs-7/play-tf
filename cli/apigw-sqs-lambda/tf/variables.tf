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
  default     = "apigw-sqs-lambda"
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
# SQS Variables
# =============================================================================

variable "queue_visibility_timeout" {
  description = "SQSキューの可視性タイムアウト（秒）。Lambdaタイムアウトより長く設定する必要がある"
  type        = number
  default     = 60
}

variable "queue_message_retention" {
  description = "メッセージ保持期間（秒）。最大14日（1209600秒）"
  type        = number
  default     = 345600 # 4 days
}

variable "dlq_max_receive_count" {
  description = "DLQに移動するまでの最大受信回数"
  type        = number
  default     = 3
}

variable "create_fifo_queue" {
  description = "FIFOキューを作成するかどうか"
  type        = bool
  default     = false
}

# =============================================================================
# Lambda Variables
# =============================================================================

variable "lambda_runtime" {
  description = "Lambdaランタイム"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_handler" {
  description = "Lambdaハンドラー"
  type        = string
  default     = "index.handler"
}

variable "lambda_timeout" {
  description = "Lambdaタイムアウト（秒）"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambdaメモリサイズ（MB）"
  type        = number
  default     = 256
}

variable "lambda_batch_size" {
  description = "SQSイベントソースマッピングのバッチサイズ"
  type        = number
  default     = 10
}

variable "lambda_source_dir" {
  description = "Lambdaソースコードのディレクトリパス（nullの場合はデフォルトのprocessor.jsを使用）"
  type        = string
  default     = null
}

variable "lambda_environment_variables" {
  description = "Lambda環境変数"
  type        = map(string)
  default     = {}
}

# =============================================================================
# API Gateway Variables
# =============================================================================

variable "api_stage_name" {
  description = "API Gatewayのステージ名"
  type        = string
  default     = "prod"
}

variable "api_endpoint_path" {
  description = "APIエンドポイントのパス"
  type        = string
  default     = "messages"
}

variable "enable_cors" {
  description = "CORSを有効にするかどうか"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "CORSで許可するオリジン"
  type        = string
  default     = "*"
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "追加のタグ"
  type        = map(string)
  default     = {}
}
