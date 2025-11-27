variable "compute_environments" {
  description = "List of Batch compute environments"
  type = list(object({
    name         = string
    type         = optional(string)
    state        = optional(string)
    service_role = optional(string)

    compute_resources = optional(object({
      type                = string
      allocation_strategy = optional(string)
      max_vcpus           = number
      min_vcpus           = optional(number)
      desired_vcpus       = optional(number)
      instance_type       = optional(list(string))
      instance_role       = optional(string)
      image_id            = optional(string)
      ec2_key_pair        = optional(string)
      bid_percentage      = optional(number)
      spot_iam_fleet_role = optional(string)
      placement_group     = optional(string)
      subnets             = list(string)
      security_group_ids  = list(string)

      ec2_configuration = optional(object({
        image_id_override = optional(string)
        image_type        = optional(string)
      }))

      launch_template = optional(object({
        launch_template_id   = optional(string)
        launch_template_name = optional(string)
        version              = optional(string)
      }))
    }))

    eks_configuration = optional(object({
      eks_cluster_arn      = string
      kubernetes_namespace = string
    }))

    update_policy = optional(object({
      job_execution_timeout_minutes = number
      terminate_jobs_on_update      = bool
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for env in var.compute_environments : env.compute_resources == null || contains(["EC2", "SPOT", "FARGATE", "FARGATE_SPOT"], env.compute_resources.type)
    ])
    error_message = "compute_resources type must be EC2, SPOT, FARGATE, or FARGATE_SPOT."
  }
}

variable "job_queues" {
  description = "List of Batch job queues"
  type = list(object({
    name                  = string
    state                 = optional(string)
    priority              = number
    scheduling_policy_arn = optional(string)

    compute_environments = list(object({
      order                    = number
      compute_environment_name = optional(string)
      compute_environment_arn  = optional(string)
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for queue in var.job_queues : queue.priority >= 0 && queue.priority <= 1000
    ])
    error_message = "Job queue priority must be between 0 and 1000."
  }
}

variable "job_definitions" {
  description = "List of Batch job definitions"
  type = list(object({
    name                  = string
    type                  = optional(string)
    platform_capabilities = optional(list(string))
    propagate_tags        = optional(bool)

    container_properties = optional(string)
    eks_properties       = optional(string)
    node_properties      = optional(string)

    parameters = optional(map(string))

    retry_strategy = optional(object({
      attempts = optional(number)
      evaluate_on_exit = optional(list(object({
        action           = string
        on_exit_code     = optional(string)
        on_reason        = optional(string)
        on_status_reason = optional(string)
      })))
    }))

    timeout_seconds     = optional(number)
    scheduling_priority = optional(number)
  }))
  default = []

  validation {
    condition = alltrue([
      for job in var.job_definitions : job.type == null || contains(["container", "multinode"], job.type)
    ])
    error_message = "Job definition type must be container or multinode."
  }
}

variable "scheduling_policies" {
  description = "List of Batch scheduling policies"
  type = list(object({
    name                = string
    compute_reservation = optional(number)
    share_decay_seconds = optional(number)

    share_distribution = optional(list(object({
      share_identifier = string
      weight_factor    = optional(number)
    })))
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
