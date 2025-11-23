variable "repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "force_delete" {
  description = "Force delete repository even if it contains images"
  type        = bool
  default     = false
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type (AES256 or KMS)"
  type        = string
  default     = "AES256"
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
}

variable "lifecycle_policy" {
  description = "Custom lifecycle policy JSON"
  type        = string
  default     = null
}

variable "enable_default_lifecycle_policy" {
  description = "Enable default lifecycle policy"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to keep"
  type        = number
  default     = 10
}

variable "untagged_image_retention_days" {
  description = "Days to retain untagged images"
  type        = number
  default     = 7
}

variable "repository_policy" {
  description = "Custom repository policy JSON"
  type        = string
  default     = null
}

variable "allowed_account_ids" {
  description = "AWS account IDs allowed to pull images"
  type        = list(string)
  default     = []
}

variable "replication_configuration" {
  description = "Replication configuration"
  type = object({
    rules = list(object({
      destinations = list(object({
        region      = string
        registry_id = string
      }))
      repository_filter = optional(object({
        filter      = string
        filter_type = string
      }))
    }))
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
