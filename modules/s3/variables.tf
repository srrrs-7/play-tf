variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning for the bucket"
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Block all public access to the bucket"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (null for AES256)"
  type        = string
  default     = null
}

variable "enable_lifecycle" {
  description = "Enable lifecycle rules"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "List of lifecycle rules"
  type = list(object({
    id                                 = string
    enabled                            = bool
    prefix                             = optional(string)
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []
}

variable "bucket_policy" {
  description = "Bucket policy JSON"
  type        = string
  default     = null
}

variable "cors_rules" {
  description = "CORS rules configuration"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default = []
}

variable "logging_target_bucket" {
  description = "Target bucket for access logs"
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefix for access logs"
  type        = string
  default     = "logs/"
}

variable "tags" {
  description = "Additional tags for the bucket"
  type        = map(string)
  default     = {}
}
