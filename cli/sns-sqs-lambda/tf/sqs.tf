# =============================================================================
# SQS Queue
# =============================================================================

resource "aws_sqs_queue" "main" {
  name = local.name_prefix

  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  receive_wait_time_seconds  = var.sqs_receive_wait_time_seconds

  sqs_managed_sse_enabled = var.enable_sqs_encryption

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

  name                      = "${local.name_prefix}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = var.enable_sqs_encryption

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dlq"
  })
}

# =============================================================================
# SQS Queue Policy (allow SNS to send messages)
# =============================================================================

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.name_prefix}-policy"
    Statement = [
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.main.arn
          }
        }
      }
    ]
  })
}
