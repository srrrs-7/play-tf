variable "name" {
  description = "Name of the SNS topic"
  type        = string
}

variable "display_name" {
  description = "Display name for the SNS topic (used for SMS subscriptions)"
  type        = string
  default     = null
}

variable "policy" {
  description = "The fully-formed AWS policy as JSON"
  type        = string
  default     = null
}

variable "topic_policy" {
  description = "The fully-formed AWS policy as JSON for the topic policy resource"
  type        = string
  default     = null
}

variable "delivery_policy" {
  description = "The SNS delivery policy as JSON"
  type        = string
  default     = null
}

variable "fifo_topic" {
  description = "Boolean indicating whether this is a FIFO topic"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enables content-based deduplication for FIFO topics"
  type        = bool
  default     = false
}

variable "kms_master_key_id" {
  description = "The ID of an AWS-managed customer master key (CMK) for Amazon SNS or a custom CMK"
  type        = string
  default     = null
}

variable "archive_policy" {
  description = "The message archive policy for FIFO topics"
  type        = string
  default     = null
}

variable "tracing_config" {
  description = "Tracing mode of an Amazon SNS topic. Valid values: PassThrough, Active"
  type        = string
  default     = null

  validation {
    condition     = var.tracing_config == null || contains(["PassThrough", "Active"], var.tracing_config)
    error_message = "tracing_config must be either PassThrough or Active."
  }
}

variable "subscriptions" {
  description = "List of SNS topic subscriptions"
  type = list(object({
    protocol                        = string
    endpoint                        = string
    confirmation_timeout_in_minutes = optional(number)
    delivery_policy                 = optional(string)
    endpoint_auto_confirms          = optional(bool)
    filter_policy                   = optional(string)
    filter_policy_scope             = optional(string)
    raw_message_delivery            = optional(bool)
    redrive_policy                  = optional(string)
    subscription_role_arn           = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for sub in var.subscriptions : contains([
        "application", "firehose", "lambda", "sms", "sqs", "email", "email-json", "http", "https"
      ], sub.protocol)
    ])
    error_message = "subscription protocol must be one of: application, firehose, lambda, sms, sqs, email, email-json, http, https."
  }
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
