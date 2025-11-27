variable "cluster_name" {
  description = "Name of the MSK cluster"
  type        = string
}

variable "cluster_type" {
  description = "Type of MSK cluster. Valid values: PROVISIONED, SERVERLESS"
  type        = string
  default     = "SERVERLESS"

  validation {
    condition     = contains(["PROVISIONED", "SERVERLESS"], var.cluster_type)
    error_message = "cluster_type must be either PROVISIONED or SERVERLESS."
  }
}

variable "kafka_version" {
  description = "Specify the desired Kafka software version (only for PROVISIONED)"
  type        = string
  default     = "3.5.1"
}

variable "number_of_broker_nodes" {
  description = "Number of broker nodes in the cluster (only for PROVISIONED)"
  type        = number
  default     = 3

  validation {
    condition     = var.number_of_broker_nodes >= 1
    error_message = "number_of_broker_nodes must be at least 1."
  }
}

variable "broker_instance_type" {
  description = "Instance type to use for the Kafka brokers (only for PROVISIONED)"
  type        = string
  default     = "kafka.t3.small"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the MSK cluster"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the MSK cluster"
  type        = list(string)
}

variable "ebs_volume_size" {
  description = "Size in GiB of the EBS volume for the broker node (only for PROVISIONED)"
  type        = number
  default     = 100

  validation {
    condition     = var.ebs_volume_size >= 1 && var.ebs_volume_size <= 16384
    error_message = "ebs_volume_size must be between 1 and 16384 GiB."
  }
}

variable "provisioned_throughput_enabled" {
  description = "Enable provisioned throughput for EBS storage"
  type        = bool
  default     = false
}

variable "provisioned_throughput_volume_throughput" {
  description = "Provisioned throughput value in MiB/s"
  type        = number
  default     = 250
}

variable "public_access_enabled" {
  description = "Enable public access to the MSK cluster"
  type        = bool
  default     = false
}

# 認証設定
variable "client_authentication_enabled" {
  description = "Enable client authentication"
  type        = bool
  default     = true
}

variable "sasl_iam_enabled" {
  description = "Enable SASL/IAM authentication"
  type        = bool
  default     = true
}

variable "sasl_scram_enabled" {
  description = "Enable SASL/SCRAM authentication"
  type        = bool
  default     = false
}

variable "unauthenticated_access_enabled" {
  description = "Enable unauthenticated access"
  type        = bool
  default     = false
}

# 暗号化設定
variable "encryption_at_rest_kms_key_arn" {
  description = "ARN of the KMS key for encryption at rest"
  type        = string
  default     = null
}

variable "encryption_in_transit_client_broker" {
  description = "Encryption setting for data in transit between clients and brokers. Valid values: TLS, TLS_PLAINTEXT, PLAINTEXT"
  type        = string
  default     = "TLS"

  validation {
    condition     = contains(["TLS", "TLS_PLAINTEXT", "PLAINTEXT"], var.encryption_in_transit_client_broker)
    error_message = "encryption_in_transit_client_broker must be TLS, TLS_PLAINTEXT, or PLAINTEXT."
  }
}

variable "encryption_in_transit_in_cluster" {
  description = "Whether data communication among the brokers should be encrypted"
  type        = bool
  default     = true
}

# 設定情報
variable "create_configuration" {
  description = "Whether to create a custom MSK configuration"
  type        = bool
  default     = false
}

variable "server_properties" {
  description = "Contents of the server.properties file for the MSK configuration"
  type        = string
  default     = <<-EOT
    auto.create.topics.enable=true
    delete.topic.enable=true
  EOT
}

variable "configuration_description" {
  description = "Description of the MSK configuration"
  type        = string
  default     = "MSK cluster configuration"
}

# ロギング設定
variable "logging_enabled" {
  description = "Enable logging for the MSK cluster"
  type        = bool
  default     = false
}

variable "cloudwatch_logs_enabled" {
  description = "Enable CloudWatch Logs for broker logs"
  type        = bool
  default     = false
}

variable "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for broker logs"
  type        = string
  default     = null
}

variable "firehose_enabled" {
  description = "Enable Firehose for broker logs"
  type        = bool
  default     = false
}

variable "firehose_delivery_stream" {
  description = "Name of the Firehose delivery stream for broker logs"
  type        = string
  default     = null
}

variable "s3_logs_enabled" {
  description = "Enable S3 for broker logs"
  type        = bool
  default     = false
}

variable "s3_logs_bucket" {
  description = "Name of the S3 bucket for broker logs"
  type        = string
  default     = null
}

variable "s3_logs_prefix" {
  description = "Prefix for S3 broker logs"
  type        = string
  default     = ""
}

# モニタリング設定
variable "enhanced_monitoring" {
  description = "Level of MSK enhanced CloudWatch monitoring. Valid values: DEFAULT, PER_BROKER, PER_TOPIC_PER_BROKER, PER_TOPIC_PER_PARTITION"
  type        = string
  default     = "DEFAULT"

  validation {
    condition     = contains(["DEFAULT", "PER_BROKER", "PER_TOPIC_PER_BROKER", "PER_TOPIC_PER_PARTITION"], var.enhanced_monitoring)
    error_message = "enhanced_monitoring must be DEFAULT, PER_BROKER, PER_TOPIC_PER_BROKER, or PER_TOPIC_PER_PARTITION."
  }
}

variable "open_monitoring_enabled" {
  description = "Enable open monitoring with Prometheus"
  type        = bool
  default     = false
}

variable "jmx_exporter_enabled" {
  description = "Enable JMX Exporter for Prometheus"
  type        = bool
  default     = false
}

variable "node_exporter_enabled" {
  description = "Enable Node Exporter for Prometheus"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
