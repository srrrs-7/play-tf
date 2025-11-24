variable "name" {
  description = "State Machine name"
  type        = string
}

variable "definition" {
  description = "State Machine definition (JSON)"
  type        = string
}

variable "role_arn" {
  description = "IAM Role ARN for State Machine execution. If null, a role will be created."
  type        = string
  default     = null
}

variable "type" {
  description = "State Machine type (STANDARD or EXPRESS)"
  type        = string
  default     = "STANDARD"
}

variable "logging_configuration" {
  description = "Logging configuration"
  type = object({
    include_execution_data = bool
    level                  = string
  })
  default = {
    include_execution_data = true
    level                  = "ALL"
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7
}

variable "tracing_enabled" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = false
}

variable "policy_statements" {
  description = "Additional IAM policy statements for the generated role"
  type = list(object({
    Effect   = string
    Action   = list(string)
    Resource = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
