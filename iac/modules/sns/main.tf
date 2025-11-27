# SNS Topic
resource "aws_sns_topic" "this" {
  name                        = var.name
  display_name                = var.display_name
  policy                      = var.policy
  delivery_policy             = var.delivery_policy
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.content_based_deduplication

  # 暗号化設定
  kms_master_key_id = var.kms_master_key_id

  # アーカイブポリシー（メッセージアーカイブ）
  archive_policy = var.archive_policy

  # トレーシング設定
  tracing_config = var.tracing_config

  tags = var.tags
}

# SNS Topic Policy（オプション）
resource "aws_sns_topic_policy" "this" {
  count = var.topic_policy != null ? 1 : 0

  arn    = aws_sns_topic.this.arn
  policy = var.topic_policy
}

# SNS Subscriptions
resource "aws_sns_topic_subscription" "this" {
  for_each = { for idx, sub in var.subscriptions : idx => sub }

  topic_arn = aws_sns_topic.this.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  # サブスクリプション設定
  confirmation_timeout_in_minutes = lookup(each.value, "confirmation_timeout_in_minutes", null)
  delivery_policy                 = lookup(each.value, "delivery_policy", null)
  endpoint_auto_confirms          = lookup(each.value, "endpoint_auto_confirms", false)
  filter_policy                   = lookup(each.value, "filter_policy", null)
  filter_policy_scope             = lookup(each.value, "filter_policy_scope", null)
  raw_message_delivery            = lookup(each.value, "raw_message_delivery", false)
  redrive_policy                  = lookup(each.value, "redrive_policy", null)
  subscription_role_arn           = lookup(each.value, "subscription_role_arn", null)
}
