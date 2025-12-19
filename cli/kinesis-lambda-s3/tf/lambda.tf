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
import base64
from datetime import datetime

s3 = boto3.client('s3')

BUCKET = os.environ['S3_BUCKET']
PREFIX = os.environ.get('S3_PREFIX', 'data/')

def handler(event, context):
    print(f"Received {len(event.get('Records', []))} records")

    records_data = []
    processed = 0
    failed = 0

    for record in event.get('Records', []):
        try:
            # Decode Kinesis data (base64)
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            print(f"Decoded payload: {payload}")

            # Parse as JSON if possible
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                data = {'raw': payload}

            # Add metadata
            data['_kinesis'] = {
                'sequenceNumber': record['kinesis']['sequenceNumber'],
                'partitionKey': record['kinesis']['partitionKey'],
                'approximateArrivalTimestamp': record['kinesis'].get('approximateArrivalTimestamp')
            }

            records_data.append(data)
            processed += 1

        except Exception as e:
            failed += 1
            print(f"Error processing record: {str(e)}")

    # Write batch to S3
    if records_data:
        timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
        filename = f"{PREFIX}{timestamp}/{context.aws_request_id}.json"

        s3.put_object(
            Bucket=BUCKET,
            Key=filename,
            Body=json.dumps(records_data, default=str),
            ContentType='application/json'
        )
        print(f"Wrote {len(records_data)} records to s3://{BUCKET}/{filename}")

    result = {
        'processed': processed,
        'failed': failed,
        'total': len(event.get('Records', [])),
        's3_location': f"s3://{BUCKET}/{filename}" if records_data else None
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
  description   = "Kinesis stream processor to S3"
  role          = aws_iam_role.lambda.arn

  filename         = var.lambda_source_path != null ? data.archive_file.lambda_external[0].output_path : data.archive_file.lambda_inline[0].output_path
  source_code_hash = var.lambda_source_path != null ? data.archive_file.lambda_external[0].output_base64sha256 : data.archive_file.lambda_inline[0].output_base64sha256

  runtime = var.lambda_runtime
  handler = var.lambda_handler

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = merge({
      S3_BUCKET  = aws_s3_bucket.main.id
      S3_PREFIX  = var.s3_prefix
      STREAM_ARN = aws_kinesis_stream.main.arn
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
# Kinesis Event Source Mapping
# =============================================================================

resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn  = aws_kinesis_stream.main.arn
  function_name     = aws_lambda_function.main.arn
  starting_position = var.lambda_starting_position
  batch_size        = var.lambda_batch_size
  enabled           = true

  maximum_batching_window_in_seconds = var.lambda_max_batching_window
  parallelization_factor             = var.lambda_parallelization_factor
}
