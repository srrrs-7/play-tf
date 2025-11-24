variable "name" {
  description = "Name to be used on all resources as prefix"
  type        = string
}

variable "ami" {
  description = "ID of AMI to use for the instance"
  type        = string
}

variable "instance_type" {
  description = "The type of instance to start"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "The VPC Subnet ID to launch in"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "A list of security group IDs to associate with"
  type        = list(string)
  default     = []
}

variable "iam_instance_profile" {
  description = "IAM Instance Profile to launch the instance with"
  type        = string
  default     = null
}

variable "user_data" {
  description = "The user data to provide when launching the instance"
  type        = string
  default     = null
}

variable "user_data_replace_on_change" {
  description = "When used in combination with user_data or user_data_base64 will trigger a destroy and recreate when set to true"
  type        = bool
  default     = false
}

variable "disable_api_termination" {
  description = "If true, enables EC2 Instance Termination Protection"
  type        = bool
  default     = false
}

variable "monitoring" {
  description = "If true, the launched EC2 instance will have detailed monitoring enabled"
  type        = bool
  default     = false
}

variable "root_block_device" {
  description = "Customize details about the root block device of the instance"
  type = object({
    volume_type           = optional(string, "gp3")
    volume_size           = optional(number, 8)
    delete_on_termination = optional(bool, true)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string, null)
  })
  default = {}
}

variable "ebs_block_devices" {
  description = "Additional EBS block devices to attach to the instance"
  type = list(object({
    device_name           = string
    volume_type           = optional(string, "gp3")
    volume_size           = optional(number, 8)
    delete_on_termination = optional(bool, true)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string, null)
  }))
  default = []
}

variable "metadata_options" {
  description = "Customize the metadata options of the instance"
  type = object({
    http_endpoint               = optional(string, "enabled")
    http_tokens                 = optional(string, "required")
    http_put_response_hop_limit = optional(number, 1)
    instance_metadata_tags      = optional(string, "enabled")
  })
  default = {}
}

variable "tags" {
  description = "A mapping of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
