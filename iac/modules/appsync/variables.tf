variable "name" {
  description = "Name of the AppSync GraphQL API"
  type        = string
}

variable "authentication_type" {
  description = "Authentication type. Valid values: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, AWS_LAMBDA"
  type        = string
  default     = "API_KEY"

  validation {
    condition     = contains(["API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT", "AWS_LAMBDA"], var.authentication_type)
    error_message = "authentication_type must be API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, or AWS_LAMBDA."
  }
}

variable "schema" {
  description = "GraphQL schema definition"
  type        = string
}

variable "additional_authentication_providers" {
  description = "List of additional authentication providers"
  type = list(object({
    authentication_type              = string
    lambda_authorizer_uri            = optional(string)
    authorizer_result_ttl_in_seconds = optional(number)
    identity_validation_expression   = optional(string)
    oidc_issuer                      = optional(string)
    oidc_client_id                   = optional(string)
    oidc_auth_ttl                    = optional(number)
    oidc_iat_ttl                     = optional(number)
    user_pool_id                     = optional(string)
    user_pool_region                 = optional(string)
    app_id_client_regex              = optional(string)
  }))
  default = []
}

# Lambda Authorizer設定
variable "lambda_authorizer_uri" {
  description = "ARN of the Lambda function for AWS_LAMBDA authentication"
  type        = string
  default     = null
}

variable "lambda_authorizer_result_ttl_in_seconds" {
  description = "Number of seconds a response should be cached for Lambda authorizer"
  type        = number
  default     = 300
}

variable "lambda_identity_validation_expression" {
  description = "Regular expression for validation of tokens before the Lambda function"
  type        = string
  default     = null
}

# OIDC設定
variable "oidc_issuer" {
  description = "Issuer for the OIDC configuration"
  type        = string
  default     = null
}

variable "oidc_client_id" {
  description = "Client identifier for the OIDC configuration"
  type        = string
  default     = null
}

variable "oidc_auth_ttl" {
  description = "Number of milliseconds a token is valid after being authenticated"
  type        = number
  default     = null
}

variable "oidc_iat_ttl" {
  description = "Number of milliseconds a token is valid after being issued"
  type        = number
  default     = null
}

# Cognito User Pool設定
variable "user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
  default     = null
}

variable "user_pool_region" {
  description = "AWS region of the Cognito User Pool"
  type        = string
  default     = null
}

variable "app_id_client_regex" {
  description = "Regular expression for validating the incoming identity"
  type        = string
  default     = null
}

variable "user_pool_default_action" {
  description = "Action that you want your GraphQL API to take when a request uses Cognito User Pool auth"
  type        = string
  default     = "ALLOW"

  validation {
    condition     = contains(["ALLOW", "DENY"], var.user_pool_default_action)
    error_message = "user_pool_default_action must be ALLOW or DENY."
  }
}

# API Key設定
variable "create_api_key" {
  description = "Whether to create an API key even if authentication_type is not API_KEY"
  type        = bool
  default     = false
}

variable "api_key_description" {
  description = "Description of the API key"
  type        = string
  default     = "API Key for AppSync"
}

variable "api_key_expires" {
  description = "RFC3339 string representation of the expiry date (max 365 days)"
  type        = string
  default     = null
}

# ロギング設定
variable "logging_enabled" {
  description = "Whether to enable CloudWatch logging"
  type        = bool
  default     = false
}

variable "cloudwatch_logs_role_arn" {
  description = "IAM role ARN for CloudWatch logging"
  type        = string
  default     = null
}

variable "field_log_level" {
  description = "Field logging level. Valid values: ALL, ERROR, NONE"
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["ALL", "ERROR", "NONE"], var.field_log_level)
    error_message = "field_log_level must be ALL, ERROR, or NONE."
  }
}

variable "exclude_verbose_content" {
  description = "Whether to exclude verbose content (headers, response headers, context, etc.) from logs"
  type        = bool
  default     = false
}

# その他の設定
variable "xray_enabled" {
  description = "Whether to enable X-Ray tracing"
  type        = bool
  default     = false
}

variable "introspection_config" {
  description = "Introspection config. Valid values: ENABLED, DISABLED"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.introspection_config)
    error_message = "introspection_config must be ENABLED or DISABLED."
  }
}

variable "query_depth_limit" {
  description = "Maximum depth a query can have"
  type        = number
  default     = null

  validation {
    condition     = var.query_depth_limit == null || (var.query_depth_limit >= 1 && var.query_depth_limit <= 75)
    error_message = "query_depth_limit must be between 1 and 75."
  }
}

variable "resolver_count_limit" {
  description = "Maximum number of resolvers that can be invoked per request"
  type        = number
  default     = null

  validation {
    condition     = var.resolver_count_limit == null || (var.resolver_count_limit >= 1 && var.resolver_count_limit <= 10000)
    error_message = "resolver_count_limit must be between 1 and 10000."
  }
}

variable "visibility" {
  description = "API visibility. Valid values: GLOBAL, PRIVATE"
  type        = string
  default     = "GLOBAL"

  validation {
    condition     = contains(["GLOBAL", "PRIVATE"], var.visibility)
    error_message = "visibility must be GLOBAL or PRIVATE."
  }
}

# Data Sources
variable "dynamodb_datasources" {
  description = "List of DynamoDB data sources"
  type = list(object({
    name                    = string
    table_name              = string
    service_role_arn        = string
    region                  = optional(string)
    use_caller_credentials  = optional(bool)
    versioned               = optional(bool)
    delta_sync_enabled      = optional(bool)
    base_table_ttl          = optional(number)
    delta_sync_table_ttl    = optional(number)
    delta_sync_table_name   = optional(string)
  }))
  default = []
}

variable "lambda_datasources" {
  description = "List of Lambda data sources"
  type = list(object({
    name             = string
    function_arn     = string
    service_role_arn = string
  }))
  default = []
}

variable "http_datasources" {
  description = "List of HTTP data sources"
  type = list(object({
    name                 = string
    endpoint             = string
    service_role_arn     = optional(string)
    authorization_type   = optional(string)
    signing_region       = optional(string)
    signing_service_name = optional(string)
  }))
  default = []
}

variable "none_datasources" {
  description = "List of None data sources (for local resolvers)"
  type = list(object({
    name        = string
    description = optional(string)
  }))
  default = []
}

# Resolvers
variable "resolvers" {
  description = "List of resolvers"
  type = list(object({
    type              = string
    field             = string
    data_source       = optional(string)
    request_template  = optional(string)
    response_template = optional(string)
    runtime_name      = optional(string)
    runtime_version   = optional(string)
    code              = optional(string)
    pipeline_config   = optional(object({
      functions = list(string)
    }))
    caching_keys      = optional(list(string))
    caching_ttl       = optional(number)
    max_batch_size    = optional(number)
  }))
  default = []
}

# Functions
variable "functions" {
  description = "List of AppSync functions for pipeline resolvers"
  type = list(object({
    name                      = string
    data_source               = string
    request_mapping_template  = optional(string)
    response_mapping_template = optional(string)
    runtime_name              = optional(string)
    runtime_version           = optional(string)
    code                      = optional(string)
    description               = optional(string)
    function_version          = optional(string)
    max_batch_size            = optional(number)
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
