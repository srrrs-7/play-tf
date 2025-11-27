# Kinesis Data Stream
resource "aws_kinesis_stream" "this" {
  name             = var.name
  retention_period = var.retention_period

  # シャード設定（ON_DEMANDモード以外で使用）
  shard_count = var.stream_mode == "ON_DEMAND" ? null : var.shard_count

  # ストリームモード設定
  stream_mode_details {
    stream_mode = var.stream_mode
  }

  # 暗号化設定
  encryption_type = var.encryption_type
  kms_key_id      = var.encryption_type == "KMS" ? var.kms_key_id : null

  # シャードレベルメトリクス
  shard_level_metrics = var.shard_level_metrics

  # 拡張ファンアウト設定
  enforce_consumer_deletion = var.enforce_consumer_deletion

  tags = var.tags
}

# Kinesis Stream Consumer（拡張ファンアウト用）
resource "aws_kinesis_stream_consumer" "this" {
  for_each = { for idx, consumer in var.stream_consumers : idx => consumer }

  name       = each.value.name
  stream_arn = aws_kinesis_stream.this.arn
}
