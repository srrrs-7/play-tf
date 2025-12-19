# =============================================================================
# Kinesis Data Stream
# =============================================================================

resource "aws_kinesis_stream" "main" {
  name             = local.name_prefix
  retention_period = var.kinesis_retention_period

  # Capacity mode
  stream_mode_details {
    stream_mode = var.kinesis_stream_mode
  }

  # Shard count (only for PROVISIONED mode)
  shard_count = var.kinesis_stream_mode == "PROVISIONED" ? var.kinesis_shard_count : null

  # Encryption
  encryption_type = var.enable_kinesis_encryption ? "KMS" : "NONE"
  kms_key_id      = var.enable_kinesis_encryption ? "alias/aws/kinesis" : null

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}
