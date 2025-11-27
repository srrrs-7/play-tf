variable "catalog_id" {
  description = "ID of the Glue Catalog (defaults to account ID)"
  type        = string
  default     = null
}

# Database設定
variable "create_database" {
  description = "Whether to create a Glue Catalog database"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Name of the Glue Catalog database"
  type        = string
  default     = null
}

variable "database_description" {
  description = "Description of the database"
  type        = string
  default     = null
}

variable "database_location_uri" {
  description = "Location of the database (S3 path)"
  type        = string
  default     = null
}

variable "database_create_table_default_permission" {
  description = "Default permissions for tables created in this database"
  type = object({
    permissions = list(string)
    principal = optional(object({
      data_lake_principal_identifier = string
    }))
  })
  default = null
}

variable "target_database" {
  description = "Configuration for a target database for resource linking"
  type = object({
    catalog_id    = string
    database_name = string
    region        = optional(string)
  })
  default = null
}

# Connection設定
variable "connections" {
  description = "List of Glue connections"
  type = list(object({
    name                  = string
    connection_type       = optional(string)
    description           = optional(string)
    connection_properties = map(string)
    physical_connection_requirements = optional(object({
      availability_zone      = optional(string)
      security_group_id_list = optional(list(string))
      subnet_id              = optional(string)
    }))
    match_criteria = optional(list(string))
  }))
  default = []
}

# Crawler設定
variable "crawlers" {
  description = "List of Glue crawlers"
  type = list(object({
    name          = string
    database_name = optional(string)
    role_arn      = string
    description   = optional(string)
    classifiers   = optional(list(string))
    configuration = optional(string)
    schedule      = optional(string)
    table_prefix  = optional(string)

    s3_targets = optional(list(object({
      path                = string
      connection_name     = optional(string)
      exclusions          = optional(list(string))
      sample_size         = optional(number)
      event_queue_arn     = optional(string)
      dlq_event_queue_arn = optional(string)
    })))

    jdbc_targets = optional(list(object({
      connection_name            = string
      path                       = string
      exclusions                 = optional(list(string))
      enable_additional_metadata = optional(list(string))
    })))

    dynamodb_targets = optional(list(object({
      path      = string
      scan_all  = optional(bool)
      scan_rate = optional(number)
    })))

    catalog_targets = optional(list(object({
      database_name       = string
      tables              = list(string)
      connection_name     = optional(string)
      event_queue_arn     = optional(string)
      dlq_event_queue_arn = optional(string)
    })))

    delta_targets = optional(list(object({
      delta_tables              = list(string)
      connection_name           = optional(string)
      write_manifest            = optional(bool)
      create_native_delta_table = optional(bool)
    })))

    schema_change_policy = optional(object({
      delete_behavior = optional(string)
      update_behavior = optional(string)
    }))

    recrawl_policy = optional(object({
      recrawl_behavior = string
    }))

    lineage_configuration = optional(object({
      crawler_lineage_settings = string
    }))

    lake_formation_configuration = optional(object({
      account_id                     = optional(string)
      use_lake_formation_credentials = optional(bool)
    }))

    security_configuration = optional(string)
  }))
  default = []
}

# Job設定
variable "jobs" {
  description = "List of Glue jobs"
  type = list(object({
    name        = string
    role_arn    = string
    description = optional(string)
    glue_version = optional(string)
    max_capacity = optional(number)
    max_retries  = optional(number)
    timeout      = optional(number)
    worker_type  = optional(string)
    number_of_workers = optional(number)

    command = object({
      script_location = string
      name            = optional(string)
      python_version  = optional(string)
      runtime         = optional(string)
    })

    default_arguments         = optional(map(string))
    non_overridable_arguments = optional(map(string))
    connections               = optional(list(string))
    max_concurrent_runs       = optional(number)
    notify_delay_after        = optional(number)
    security_configuration    = optional(string)
    execution_class           = optional(string)
  }))
  default = []
}

# Trigger設定
variable "triggers" {
  description = "List of Glue triggers"
  type = list(object({
    name              = string
    type              = string
    description       = optional(string)
    enabled           = optional(bool)
    schedule          = optional(string)
    workflow_name     = optional(string)
    start_on_creation = optional(bool)

    actions = list(object({
      job_name               = optional(string)
      crawler_name           = optional(string)
      arguments              = optional(map(string))
      timeout                = optional(number)
      security_configuration = optional(string)
      notify_delay_after     = optional(number)
    }))

    predicate = optional(object({
      logical = optional(string)
      conditions = list(object({
        job_name         = optional(string)
        crawler_name     = optional(string)
        state            = optional(string)
        crawl_state      = optional(string)
        logical_operator = optional(string)
      }))
    }))

    event_batching_condition = optional(object({
      batch_size   = number
      batch_window = optional(number)
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for trigger in var.triggers : contains(["SCHEDULED", "CONDITIONAL", "ON_DEMAND", "EVENT"], trigger.type)
    ])
    error_message = "Trigger type must be SCHEDULED, CONDITIONAL, ON_DEMAND, or EVENT."
  }
}

# Workflow設定
variable "workflows" {
  description = "List of Glue workflows"
  type = list(object({
    name                   = string
    description            = optional(string)
    default_run_properties = optional(map(string))
    max_concurrent_runs    = optional(number)
  }))
  default = []
}

# Security Configuration設定
variable "create_security_configuration" {
  description = "Whether to create a security configuration"
  type        = bool
  default     = false
}

variable "security_configuration_name" {
  description = "Name of the security configuration"
  type        = string
  default     = null
}

variable "cloudwatch_encryption" {
  description = "CloudWatch encryption configuration"
  type = object({
    mode        = string
    kms_key_arn = optional(string)
  })
  default = null

  validation {
    condition     = var.cloudwatch_encryption == null || contains(["DISABLED", "SSE-KMS"], var.cloudwatch_encryption.mode)
    error_message = "cloudwatch_encryption mode must be DISABLED or SSE-KMS."
  }
}

variable "job_bookmarks_encryption" {
  description = "Job bookmarks encryption configuration"
  type = object({
    mode        = string
    kms_key_arn = optional(string)
  })
  default = null

  validation {
    condition     = var.job_bookmarks_encryption == null || contains(["DISABLED", "CSE-KMS"], var.job_bookmarks_encryption.mode)
    error_message = "job_bookmarks_encryption mode must be DISABLED or CSE-KMS."
  }
}

variable "s3_encryption" {
  description = "S3 encryption configuration"
  type = object({
    mode        = string
    kms_key_arn = optional(string)
  })
  default = null

  validation {
    condition     = var.s3_encryption == null || contains(["DISABLED", "SSE-KMS", "SSE-S3"], var.s3_encryption.mode)
    error_message = "s3_encryption mode must be DISABLED, SSE-KMS, or SSE-S3."
  }
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
