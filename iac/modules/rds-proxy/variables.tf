variable "name" {
  description = "Name of the RDS Proxy"
  type        = string
}

variable "debug_logging" {
  description = "Whether the proxy includes detailed information about SQL statements"
  type        = bool
  default     = false
}

variable "engine_family" {
  description = "The kinds of databases that the proxy can connect to. Valid values: MYSQL, POSTGRESQL, SQLSERVER"
  type        = string

  validation {
    condition     = contains(["MYSQL", "POSTGRESQL", "SQLSERVER"], var.engine_family)
    error_message = "engine_family must be MYSQL, POSTGRESQL, or SQLSERVER."
  }
}

variable "idle_client_timeout" {
  description = "Number of seconds a connection to the proxy can be inactive before the proxy disconnects it"
  type        = number
  default     = 1800

  validation {
    condition     = var.idle_client_timeout >= 1 && var.idle_client_timeout <= 28800
    error_message = "idle_client_timeout must be between 1 and 28800 seconds."
  }
}

variable "require_tls" {
  description = "Whether TLS/SSL is required for connections to the proxy"
  type        = bool
  default     = true
}

variable "role_arn" {
  description = "IAM role that the proxy uses to access secrets in AWS Secrets Manager"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups to associate with the proxy"
  type        = list(string)
}

variable "vpc_subnet_ids" {
  description = "List of VPC subnets to associate with the proxy"
  type        = list(string)
}

# 認証設定
variable "auth_configs" {
  description = "Configuration for proxy authentication"
  type = list(object({
    auth_scheme               = optional(string)
    client_password_auth_type = optional(string)
    description               = optional(string)
    iam_auth                  = optional(string)
    secret_arn                = string
    username                  = optional(string)
  }))

  validation {
    condition = alltrue([
      for auth in var.auth_configs : auth.auth_scheme == null || contains(["SECRETS"], auth.auth_scheme)
    ])
    error_message = "auth_scheme must be SECRETS."
  }

  validation {
    condition = alltrue([
      for auth in var.auth_configs : auth.iam_auth == null || contains(["DISABLED", "REQUIRED"], auth.iam_auth)
    ])
    error_message = "iam_auth must be DISABLED or REQUIRED."
  }

  validation {
    condition = alltrue([
      for auth in var.auth_configs : auth.client_password_auth_type == null || contains(["MYSQL_NATIVE_PASSWORD", "POSTGRES_SCRAM_SHA_256", "POSTGRES_MD5", "SQL_SERVER_AUTHENTICATION"], auth.client_password_auth_type)
    ])
    error_message = "client_password_auth_type must be MYSQL_NATIVE_PASSWORD, POSTGRES_SCRAM_SHA_256, POSTGRES_MD5, or SQL_SERVER_AUTHENTICATION."
  }
}

# 接続プール設定
variable "connection_borrow_timeout" {
  description = "Number of seconds for a proxy to wait for a connection to become available"
  type        = number
  default     = 120

  validation {
    condition     = var.connection_borrow_timeout >= 1 && var.connection_borrow_timeout <= 3600
    error_message = "connection_borrow_timeout must be between 1 and 3600 seconds."
  }
}

variable "init_query" {
  description = "One or more SQL statements to send when opening each new connection"
  type        = string
  default     = null
}

variable "max_connections_percent" {
  description = "Maximum size of the connection pool for each target"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections_percent >= 1 && var.max_connections_percent <= 100
    error_message = "max_connections_percent must be between 1 and 100."
  }
}

variable "max_idle_connections_percent" {
  description = "Controls how actively the proxy closes idle database connections"
  type        = number
  default     = 50

  validation {
    condition     = var.max_idle_connections_percent >= 0 && var.max_idle_connections_percent <= 100
    error_message = "max_idle_connections_percent must be between 0 and 100."
  }
}

variable "session_pinning_filters" {
  description = "Controls which session states can be shared between connections"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for filter in var.session_pinning_filters : contains(["EXCLUDE_VARIABLE_SETS"], filter)
    ])
    error_message = "session_pinning_filters must contain only EXCLUDE_VARIABLE_SETS."
  }
}

# ターゲット設定
variable "db_instance_targets" {
  description = "List of RDS DB instances to register with the proxy"
  type = list(object({
    db_instance_identifier = string
  }))
  default = []
}

variable "db_cluster_targets" {
  description = "List of RDS DB clusters to register with the proxy"
  type = list(object({
    db_cluster_identifier = string
  }))
  default = []
}

# 追加エンドポイント設定
variable "proxy_endpoints" {
  description = "List of additional proxy endpoints"
  type = list(object({
    name                   = string
    vpc_subnet_ids         = optional(list(string))
    vpc_security_group_ids = optional(list(string))
    target_role            = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for endpoint in var.proxy_endpoints : endpoint.target_role == null || contains(["READ_WRITE", "READ_ONLY"], endpoint.target_role)
    ])
    error_message = "target_role must be READ_WRITE or READ_ONLY."
  }
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
