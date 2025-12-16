# =============================================================================
# Dead Letter Queue (DLQ)
# =============================================================================
# 処理失敗したメッセージを保持するキュー
# maxReceiveCount回失敗するとこのキューに移動

resource "aws_sqs_queue" "dlq" {
  name = var.create_fifo_queue ? "${local.name_prefix}-dlq.fifo" : "${local.name_prefix}-dlq"

  # FIFO設定（FIFOキューの場合のみ）
  fifo_queue                  = var.create_fifo_queue
  content_based_deduplication = var.create_fifo_queue

  # メッセージ保持期間（DLQは長めに設定）
  message_retention_seconds = 1209600 # 14 days (maximum)

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-dlq"
    Type = "DLQ"
  })
}

# =============================================================================
# Main SQS Queue
# =============================================================================
# API Gatewayからメッセージを受信し、Lambdaに配信するメインキュー

resource "aws_sqs_queue" "main" {
  name = var.create_fifo_queue ? "${local.name_prefix}-queue.fifo" : "${local.name_prefix}-queue"

  # FIFO設定
  fifo_queue                  = var.create_fifo_queue
  content_based_deduplication = var.create_fifo_queue

  # タイムアウト設定
  visibility_timeout_seconds = var.queue_visibility_timeout
  message_retention_seconds  = var.queue_message_retention

  # DLQ設定（RedrivePolicy）
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.dlq_max_receive_count
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-queue"
    Type = "Main"
  })
}

# =============================================================================
# SQS Queue Policy
# =============================================================================
# API Gatewayからのメッセージ送信を許可

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAPIGateway"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = "${aws_api_gateway_rest_api.main.execution_arn}/*"
          }
        }
      }
    ]
  })
}
