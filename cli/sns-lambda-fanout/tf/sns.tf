# =============================================================================
# SNS Topic
# =============================================================================

resource "aws_sns_topic" "main" {
  name         = local.name_prefix
  display_name = var.sns_display_name

  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

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
# SNS Subscriptions (to Lambda functions)
# =============================================================================

resource "aws_sns_topic_subscription" "lambda" {
  for_each = { for idx, func in var.lambda_functions : func.name => func }

  topic_arn     = aws_sns_topic.main.arn
  protocol      = "lambda"
  endpoint      = aws_lambda_function.main[each.key].arn
  filter_policy = each.value.filter_policy
}
