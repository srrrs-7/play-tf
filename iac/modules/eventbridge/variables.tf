variable "name" {
  description = "Rule name"
  type        = string
}

variable "description" {
  description = "Rule description"
  type        = string
  default     = null
}

variable "schedule_expression" {
  description = "Schedule expression (e.g., cron(0 20 * * ? *) or rate(5 minutes))"
  type        = string
  default     = null
}

variable "event_pattern" {
  description = "Event pattern (JSON)"
  type        = string
  default     = null
}

variable "is_enabled" {
  description = "Whether the rule is enabled"
  type        = bool
  default     = true
}

variable "targets" {
  description = "List of targets"
  type = list(object({
    arn        = string
    target_id  = optional(string)
    role_arn   = optional(string)
    input      = optional(string)
    input_path = optional(string)
    input_transformer = optional(object({
      input_paths    = map(string)
      input_template = string
    }))
    retry_policy = optional(object({
      maximum_event_age_in_seconds = number
      maximum_retry_attempts       = number
    }))
    dead_letter_arn = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
