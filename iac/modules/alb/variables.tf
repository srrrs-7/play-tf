variable "alb_name" {
  description = "ALB名"
  type        = string
}

variable "internal" {
  description = "内部向けロードバランサーか"
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "ALBに関連付けるセキュリティグループIDリスト"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "ALBを配置するサブネットIDリスト"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "enable_deletion_protection" {
  description = "削除保護を有効化するか"
  type        = bool
  default     = false
}

variable "enable_http2" {
  description = "HTTP/2を有効化するか"
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "アイドルタイムアウト（秒）"
  type        = number
  default     = 60
}

variable "drop_invalid_header_fields" {
  description = "無効なヘッダーフィールドを破棄するか"
  type        = bool
  default     = false
}

variable "access_logs" {
  description = "アクセスログ設定"
  type = object({
    bucket  = string
    prefix  = optional(string)
    enabled = optional(bool)
  })
  default = null
}

variable "target_groups" {
  description = "ターゲットグループ設定"
  type = map(object({
    name                          = string
    port                          = number
    protocol                      = optional(string)
    protocol_version              = optional(string)
    target_type                   = optional(string)
    deregistration_delay          = optional(number)
    slow_start                    = optional(number)
    load_balancing_algorithm_type = optional(string)
    health_check = object({
      enabled             = optional(bool)
      healthy_threshold   = optional(number)
      unhealthy_threshold = optional(number)
      timeout             = optional(number)
      interval            = optional(number)
      path                = optional(string)
      port                = optional(string)
      protocol            = optional(string)
      matcher             = optional(string)
    })
    stickiness = optional(object({
      type            = string
      cookie_duration = optional(number)
      cookie_name     = optional(string)
      enabled         = optional(bool)
    }))
  }))
  default = {}
}

variable "create_http_listener" {
  description = "HTTPリスナーを作成するか"
  type        = bool
  default     = true
}

variable "http_listener_redirect_to_https" {
  description = "HTTPからHTTPSへリダイレクトするか"
  type        = bool
  default     = true
}

variable "create_https_listener" {
  description = "HTTPSリスナーを作成するか"
  type        = bool
  default     = false
}

variable "ssl_policy" {
  description = "HTTPSリスナーのSSLポリシー"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "certificate_arn" {
  description = "ACM証明書ARN"
  type        = string
  default     = null
}

variable "additional_certificate_arns" {
  description = "追加のACM証明書ARNリスト"
  type        = list(string)
  default     = []
}

variable "listener_rules" {
  description = "リスナールール設定"
  type = map(object({
    listener_type    = string # "http" or "https"
    priority         = number
    action_type      = optional(string)
    target_group_key = optional(string)
    host_headers     = optional(list(string))
    path_patterns    = optional(list(string))
    http_headers = optional(list(object({
      name   = string
      values = list(string)
    })))
    source_ips = optional(list(string))
    redirect = optional(object({
      host        = optional(string)
      path        = optional(string)
      port        = optional(string)
      protocol    = optional(string)
      query       = optional(string)
      status_code = optional(string)
    }))
    fixed_response = optional(object({
      content_type = string
      message_body = optional(string)
      status_code  = optional(string)
    }))
  }))
  default = {}
}

variable "create_security_group" {
  description = "ALB用セキュリティグループを作成するか"
  type        = bool
  default     = false
}

variable "security_group_ingress_rules" {
  description = "セキュリティグループのインバウンドルール"
  type = list(object({
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string))
    ipv6_cidr_blocks = optional(list(string))
    security_groups  = optional(list(string))
    description      = optional(string)
  }))
  default = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTP"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTPS"
    }
  ]
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
