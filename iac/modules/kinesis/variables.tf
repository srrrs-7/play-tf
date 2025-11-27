variable "name" {
  description = "Name of the Kinesis stream"
  type        = string
}

variable "retention_period" {
  description = "Length of time data records are accessible after they are added to the stream (hours)"
  type        = number
  default     = 24

  validation {
    condition     = var.retention_period >= 24 && var.retention_period <= 8760
    error_message = "retention_period must be between 24 and 8760 hours."
  }
}

variable "shard_count" {
  description = "Number of shards that the stream will use (ignored when stream_mode is ON_DEMAND)"
  type        = number
  default     = 1

  validation {
    condition     = var.shard_count >= 1
    error_message = "shard_count must be at least 1."
  }
}

variable "stream_mode" {
  description = "Specifies the capacity mode of the stream. Valid values: PROVISIONED, ON_DEMAND"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["PROVISIONED", "ON_DEMAND"], var.stream_mode)
    error_message = "stream_mode must be either PROVISIONED or ON_DEMAND."
  }
}

variable "encryption_type" {
  description = "The encryption type to use. Valid values: NONE, KMS"
  type        = string
  default     = "KMS"

  validation {
    condition     = contains(["NONE", "KMS"], var.encryption_type)
    error_message = "encryption_type must be either NONE or KMS."
  }
}

variable "kms_key_id" {
  description = "The GUID for the customer-managed AWS KMS key to use for encryption (alias/aws/kinesis for AWS managed key)"
  type        = string
  default     = "alias/aws/kinesis"
}

variable "shard_level_metrics" {
  description = "List of shard-level CloudWatch metrics which can be enabled for the stream"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for metric in var.shard_level_metrics : contains([
        "IncomingBytes",
        "IncomingRecords",
        "OutgoingBytes",
        "OutgoingRecords",
        "WriteProvisionedThroughputExceeded",
        "ReadProvisionedThroughputExceeded",
        "IteratorAgeMilliseconds",
        "ALL"
      ], metric)
    ])
    error_message = "Invalid shard_level_metrics value."
  }
}

variable "enforce_consumer_deletion" {
  description = "Whether to enforce consumer deletion when deleting the stream"
  type        = bool
  default     = false
}

variable "stream_consumers" {
  description = "List of stream consumers for enhanced fan-out"
  type = list(object({
    name = string
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
