# MSK Cluster Configuration
resource "aws_msk_configuration" "this" {
  count = var.create_configuration ? 1 : 0

  name              = "${var.cluster_name}-config"
  kafka_versions    = [var.kafka_version]
  server_properties = var.server_properties

  description = var.configuration_description
}

# MSK Cluster (Provisioned)
resource "aws_msk_cluster" "this" {
  count = var.cluster_type == "PROVISIONED" ? 1 : 0

  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.subnet_ids
    security_groups = var.security_group_ids

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size

        dynamic "provisioned_throughput" {
          for_each = var.provisioned_throughput_enabled ? [1] : []
          content {
            enabled           = true
            volume_throughput = var.provisioned_throughput_volume_throughput
          }
        }
      }
    }

    connectivity_info {
      public_access {
        type = var.public_access_enabled ? "SERVICE_PROVIDED_EIPS" : "DISABLED"
      }
    }
  }

  # クライアント認証設定
  dynamic "client_authentication" {
    for_each = var.client_authentication_enabled ? [1] : []
    content {
      sasl {
        iam   = var.sasl_iam_enabled
        scram = var.sasl_scram_enabled
      }
      unauthenticated = var.unauthenticated_access_enabled
    }
  }

  # 暗号化設定
  encryption_info {
    encryption_at_rest_kms_key_arn = var.encryption_at_rest_kms_key_arn

    encryption_in_transit {
      client_broker = var.encryption_in_transit_client_broker
      in_cluster    = var.encryption_in_transit_in_cluster
    }
  }

  # 設定情報
  dynamic "configuration_info" {
    for_each = var.create_configuration ? [1] : []
    content {
      arn      = aws_msk_configuration.this[0].arn
      revision = aws_msk_configuration.this[0].latest_revision
    }
  }

  # ロギング設定
  dynamic "logging_info" {
    for_each = var.logging_enabled ? [1] : []
    content {
      broker_logs {
        dynamic "cloudwatch_logs" {
          for_each = var.cloudwatch_logs_enabled ? [1] : []
          content {
            enabled   = true
            log_group = var.cloudwatch_log_group
          }
        }

        dynamic "firehose" {
          for_each = var.firehose_enabled ? [1] : []
          content {
            enabled         = true
            delivery_stream = var.firehose_delivery_stream
          }
        }

        dynamic "s3" {
          for_each = var.s3_logs_enabled ? [1] : []
          content {
            enabled = true
            bucket  = var.s3_logs_bucket
            prefix  = var.s3_logs_prefix
          }
        }
      }
    }
  }

  # 拡張モニタリング
  enhanced_monitoring = var.enhanced_monitoring

  # オープンモニタリング（Prometheus）
  dynamic "open_monitoring" {
    for_each = var.open_monitoring_enabled ? [1] : []
    content {
      prometheus {
        jmx_exporter {
          enabled_in_broker = var.jmx_exporter_enabled
        }
        node_exporter {
          enabled_in_broker = var.node_exporter_enabled
        }
      }
    }
  }

  tags = var.tags
}

# MSK Serverless Cluster
resource "aws_msk_serverless_cluster" "this" {
  count = var.cluster_type == "SERVERLESS" ? 1 : 0

  cluster_name = var.cluster_name

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = var.tags
}
