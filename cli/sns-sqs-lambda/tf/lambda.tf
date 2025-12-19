# =============================================================================
# Lambda Function
# =============================================================================

# Inline Lambda code
data "archive_file" "lambda_inline" {
  count = var.lambda_source_path == null ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.terraform/lambda_inline.zip"

  source {
    content  = <<-PYTHON
import json
import os

def handler(event, context):
    print(f"Received {len(event.get('Records', []))} records")

    processed = 0
    failed = 0

    for record in event.get('Records', []):
        try:
            # Get the message body from SQS record
            sqs_body = record['body']
            print(f"SQS Body: {sqs_body}")

            # Parse SNS message if not raw delivery
            try:
                sns_message = json.loads(sqs_body)
                if 'Message' in sns_message:
                    # This is an SNS wrapped message
                    actual_message = json.loads(sns_message['Message'])
                    sns_attributes = sns_message.get('MessageAttributes', {})
                    print(f"SNS Message: {json.dumps(actual_message)}")
                    print(f"SNS Attributes: {json.dumps(sns_attributes)}")
                else:
                    # Raw message delivery
                    actual_message = sns_message
                    print(f"Raw Message: {json.dumps(actual_message)}")
            except json.JSONDecodeError:
                # Plain text message
                actual_message = sqs_body
                print(f"Plain Text Message: {actual_message}")

            # Process the message here
            # Add your business logic

            processed += 1
            print(f"Successfully processed message")

        except Exception as e:
            failed += 1
            print(f"Error processing record: {str(e)}")
            raise e  # Re-raise to use SQS retry

    result = {
        'processed': processed,
        'failed': failed,
        'total': len(event.get('Records', []))
    }
    print(f"Processing complete: {json.dumps(result)}")

    return result
PYTHON
    filename = "index.py"
  }
}

# External Lambda source
data "archive_file" "lambda_external" {
  count = var.lambda_source_path != null ? 1 : 0

  type        = "zip"
  source_dir  = var.lambda_source_path
  output_path = "${path.module}/.terraform/lambda_external.zip"
}

# Lambda function
resource "aws_lambda_function" "main" {
  function_name = local.name_prefix
  description   = "SNS-SQS message processor"
  role          = aws_iam_role.lambda.arn

  filename         = var.lambda_source_path != null ? data.archive_file.lambda_external[0].output_path : data.archive_file.lambda_inline[0].output_path
  source_code_hash = var.lambda_source_path != null ? data.archive_file.lambda_external[0].output_base64sha256 : data.archive_file.lambda_inline[0].output_base64sha256

  runtime = var.lambda_runtime
  handler = var.lambda_handler

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = merge({
      SNS_TOPIC_ARN = aws_sns_topic.main.arn
      QUEUE_URL     = aws_sqs_queue.main.url
    }, var.lambda_environment_variables)
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

# Lambda CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs"
  })
}

# =============================================================================
# SQS Event Source Mapping
# =============================================================================

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.main.arn
  batch_size       = var.lambda_batch_size
  enabled          = true
}
