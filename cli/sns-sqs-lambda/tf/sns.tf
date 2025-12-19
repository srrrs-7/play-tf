# =============================================================================
# SNS Topic
# =============================================================================

resource "aws_sns_topic" "main" {
  name         = local.name_prefix
  display_name = var.sns_display_name

  # Encryption
  kms_master_key_id = var.enable_sns_encryption ? coalesce(var.sns_kms_master_key_id, "alias/aws/sns") : null

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

# =============================================================================
# SNS Topic Policy
# =============================================================================

resource "aws_sns_topic_policy" "main" {
  arn = aws_sns_topic.main.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.name_prefix}-policy"
    Statement = [
      {
        Sid    = "AllowSameAccountPublish"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.main.arn
      }
    ]
  })
}

# =============================================================================
# SNS Subscription (to SQS)
# =============================================================================

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn            = aws_sns_topic.main.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.main.arn
  raw_message_delivery = var.raw_message_delivery

  # Optional filter policy
  filter_policy = var.sns_filter_policy
}
