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
import boto3
import os
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    print(f"Received {len(event.get('Records', []))} records")

    processed = 0
    failed = 0

    for record in event.get('Records', []):
        try:
            # Parse message body
            body = json.loads(record['body'])
            print(f"Processing message: {json.dumps(body)}")

            # Add metadata
            item = {
                'id': body.get('id', str(uuid.uuid4())),
                'data': body,
                'message_id': record.get('messageId'),
                'processed_at': datetime.utcnow().isoformat(),
                'source': 'sqs'
            }

            # Save to DynamoDB
            table.put_item(Item=item)
            processed += 1
            print(f"Successfully saved item: {item['id']}")

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
  description   = "SQS message processor for DynamoDB"
  role          = aws_iam_role.lambda.arn

  filename         = var.lambda_source_path != null ? data.archive_file.lambda_external[0].output_path : data.archive_file.lambda_inline[0].output_path
  source_code_hash = var.lambda_source_path != null ? data.archive_file.lambda_external[0].output_base64sha256 : data.archive_file.lambda_inline[0].output_base64sha256

  runtime = var.lambda_runtime
  handler = var.lambda_handler

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : null

  environment {
    variables = merge({
      DYNAMODB_TABLE = aws_dynamodb_table.main.name
      QUEUE_URL      = aws_sqs_queue.main.url
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

  maximum_batching_window_in_seconds = var.lambda_max_batching_window

  scaling_config {
    maximum_concurrency = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : 1000
  }
}
