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
import urllib.parse

s3 = boto3.client('s3')

DEST_BUCKET = os.environ['DEST_BUCKET']
DEST_PREFIX = os.environ.get('DEST_PREFIX', 'output/')

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")

    processed = 0
    failed = 0

    for record in event.get('Records', []):
        try:
            # Get source bucket and key
            source_bucket = record['s3']['bucket']['name']
            source_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            event_name = record.get('eventName', '')

            print(f"Processing: s3://{source_bucket}/{source_key}")
            print(f"Event: {event_name}")

            # Get the object
            response = s3.get_object(Bucket=source_bucket, Key=source_key)
            content = response['Body'].read()
            content_type = response.get('ContentType', 'application/octet-stream')

            # Process the content
            # This example just copies the file - add your transformation logic here
            processed_content = process_content(content, content_type)

            # Generate destination key
            filename = os.path.basename(source_key)
            dest_key = f"{DEST_PREFIX}{filename}"

            # Upload to destination bucket
            s3.put_object(
                Bucket=DEST_BUCKET,
                Key=dest_key,
                Body=processed_content,
                ContentType=content_type,
                Metadata={
                    'source-bucket': source_bucket,
                    'source-key': source_key,
                    'processed-by': context.function_name
                }
            )

            print(f"Uploaded to: s3://{DEST_BUCKET}/{dest_key}")
            processed += 1

        except Exception as e:
            failed += 1
            print(f"Error processing record: {str(e)}")
            raise e

    result = {
        'processed': processed,
        'failed': failed,
        'total': len(event.get('Records', []))
    }
    print(f"Processing complete: {json.dumps(result)}")

    return result

def process_content(content, content_type):
    """
    Process the content - customize this function for your needs.
    Examples:
    - Image resizing
    - Text transformation
    - File format conversion
    - Data validation and enrichment
    """
    # Default: return content unchanged
    # Add your processing logic here
    return content
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
  description   = "S3 event-driven file processor"
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
      SOURCE_BUCKET = aws_s3_bucket.source.id
      DEST_BUCKET   = aws_s3_bucket.dest.id
      DEST_PREFIX   = var.dest_prefix
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

# Lambda permission for S3
resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}
