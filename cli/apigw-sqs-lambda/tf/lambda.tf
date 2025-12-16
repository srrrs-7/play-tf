# =============================================================================
# Lambda IAM Role
# =============================================================================

# Trust Policy
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-processor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "IAM Role for Lambda SQS processor"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-processor-role"
  })
}

# Basic Execution Role（CloudWatch Logsへの書き込み）
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SQS Execution Role（SQSからのメッセージ受信、削除）
resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# =============================================================================
# Lambda Function Source Code
# =============================================================================

# デフォルトのLambdaコード
locals {
  default_lambda_code = <<-EOF
    exports.handler = async (event) => {
        console.log('Processing', event.Records.length, 'messages from SQS');

        const results = [];
        for (const record of event.Records) {
            try {
                const body = JSON.parse(record.body);
                console.log('Processing message:', record.messageId);
                console.log('Message body:', JSON.stringify(body, null, 2));

                // Add your business logic here
                const result = {
                    messageId: record.messageId,
                    body: body,
                    processedAt: new Date().toISOString(),
                    status: 'success'
                };

                results.push(result);
                console.log('Processed successfully:', record.messageId);
            } catch (error) {
                console.error('Error processing message:', record.messageId, error);
                throw error; // Rethrow to trigger retry/DLQ
            }
        }

        console.log('Processed', results.length, 'messages');
        return { batchItemFailures: [] };
    };
  EOF
}

# Lambdaコードをzipに圧縮
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = local.default_lambda_code
    filename = "index.js"
  }
}

# =============================================================================
# Lambda Function
# =============================================================================

resource "aws_lambda_function" "processor" {
  function_name = "${local.name_prefix}-processor"
  role          = aws_iam_role.lambda.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = merge(
      {
        QUEUE_URL = aws_sqs_queue.main.url
        DLQ_URL   = aws_sqs_queue.dlq.url
      },
      var.lambda_environment_variables
    )
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-processor"
  })
}

# =============================================================================
# SQS Event Source Mapping
# =============================================================================
# SQSキューからLambdaへのトリガー設定

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = var.lambda_batch_size

  # 部分的なバッチ失敗のレポートを有効化
  function_response_types = ["ReportBatchItemFailures"]
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================
# Lambda関数のログを保持

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-processor-logs"
  })
}
