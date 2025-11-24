variable "name" {
  description = "Name to be used on all resources as prefix"
  type        = string
}

variable "create_cluster" {
  description = "Whether to create an ECS cluster"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the ECS cluster (required if create_cluster is true, or if using existing cluster by name)"
  type        = string
  default     = null
}

variable "cluster_id" {
  description = "ID of the existing ECS cluster (required if create_cluster is false)"
  type        = string
  default     = null
}

variable "container_insights" {
  description = "Enable Container Insights"
  type        = bool
  default     = true
}

variable "container_definitions" {
  description = "Container definitions in JSON format"
  type        = string
}

variable "requires_compatibilities" {
  description = "Set of launch types required by the task"
  type        = list(string)
  default     = ["FARGATE"]
}

variable "network_mode" {
  description = "Docker networking mode to use for the containers in the task"
  type        = string
  default     = "awsvpc"

  validation {
    condition     = contains(["none", "bridge", "awsvpc", "host"], var.network_mode)
    error_message = "network_mode must be one of: none, bridge, awsvpc, host."
  }
}

variable "cpu" {
  description = "Number of cpu units used by the task"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Amount (in MiB) of memory used by the task"
  type        = number
  default     = 512
}

variable "execution_role_arn" {
  description = "ARN of the task execution role"
  type        = string
  default     = null
}

variable "task_role_arn" {
  description = "ARN of the task role"
  type        = string
  default     = null
}

variable "operating_system_family" {
  description = "OS family"
  type        = string
  default     = "LINUX"

  validation {
    condition     = contains(["LINUX", "WINDOWS_SERVER_2019_FULL", "WINDOWS_SERVER_2019_CORE", "WINDOWS_SERVER_2022_FULL", "WINDOWS_SERVER_2022_CORE"], var.operating_system_family)
    error_message = "operating_system_family must be a valid AWS ECS OS family."
  }
}

variable "cpu_architecture" {
  description = "CPU architecture"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be either X86_64 or ARM64."
  }
}

variable "desired_count" {
  description = "Number of instances of the task definition"
  type        = number
  default     = 1
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Assign a public IP address to the ENI"
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = "ARN of the target group"
  type        = string
  default     = null
}

variable "container_name" {
  description = "Name of the container to associate with the load balancer"
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port on the container to associate with the load balancer"
  type        = number
  default     = null
}

variable "capacity_provider_strategy" {
  description = "Capacity provider strategy"
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number)
  }))
  default = []
}

variable "create_log_group" {
  description = "Create CloudWatch Log Group"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
