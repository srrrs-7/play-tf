# =============================================================================
# SQS Queue
# =============================================================================

resource "aws_sqs_queue" "main" {
  name = var.enable_fifo_queue ? "${local.name_prefix}.fifo" : local.name_prefix

  visibility_timeout_seconds  = var.sqs_visibility_timeout_seconds
  message_retention_seconds   = var.sqs_message_retention_seconds
  max_message_size            = var.sqs_max_message_size
  delay_seconds               = var.sqs_delay_seconds
  receive_wait_time_seconds   = var.sqs_receive_wait_time_seconds

  # FIFO settings
  fifo_queue                  = var.enable_fifo_queue
  content_based_deduplication = var.enable_fifo_queue ? var.fifo_content_based_deduplication : null

  # Encryption
  sqs_managed_sse_enabled = var.enable_sqs_encryption

  # Dead letter queue
  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.dlq_max_receive_count
  }) : null

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

# =============================================================================
# Dead Letter Queue
# =============================================================================

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name = var.enable_fifo_queue ? "${local.name_prefix}-dlq.fifo" : "${local.name_prefix}-dlq"

  message_retention_seconds = 1209600 # 14 days
  fifo_queue                = var.enable_fifo_queue
  sqs_managed_sse_enabled   = var.enable_sqs_encryption

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dlq"
  })
}

# =============================================================================
# SQS Queue Policy
# =============================================================================

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.name_prefix}-policy"
    Statement = [
      {
        Sid    = "AllowSameAccountSendMessage"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}
