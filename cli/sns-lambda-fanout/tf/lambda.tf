# =============================================================================
# Lambda Functions (Fan-out)
# =============================================================================

# Inline Lambda code
data "archive_file" "lambda_inline" {
  type        = "zip"
  output_path = "${path.module}/.terraform/lambda_inline.zip"

  source {
    content  = <<-PYTHON
import json
import os

def handler(event, context):
    function_name = context.function_name
    print(f"Function: {function_name}")
    print(f"Received {len(event.get('Records', []))} records")

    processed = 0

    for record in event.get('Records', []):
        try:
            sns = record.get('Sns', {})
            message = sns.get('Message', '')
            subject = sns.get('Subject', '')
            attributes = sns.get('MessageAttributes', {})

            print(f"Subject: {subject}")
            print(f"Message: {message}")
            print(f"Attributes: {json.dumps(attributes)}")

            # Parse message if JSON
            try:
                data = json.loads(message)
                print(f"Parsed data: {json.dumps(data)}")
            except json.JSONDecodeError:
                data = message
                print(f"Plain text message: {data}")

            # Process the message here
            # Add your business logic for this specific fan-out function

            processed += 1

        except Exception as e:
            print(f"Error processing record: {str(e)}")
            raise e

    result = {
        'function': function_name,
        'processed': processed,
        'total': len(event.get('Records', []))
    }
    print(f"Processing complete: {json.dumps(result)}")

    return result
PYTHON
    filename = "index.py"
  }
}

# Lambda functions
resource "aws_lambda_function" "main" {
  for_each = { for idx, func in var.lambda_functions : func.name => func }

  function_name = "${local.name_prefix}-${each.value.name}"
  description   = each.value.description
  role          = aws_iam_role.lambda.arn

  filename         = each.value.source_path != null ? "${each.value.source_path}.zip" : data.archive_file.lambda_inline.output_path
  source_code_hash = each.value.source_path != null ? filebase64sha256("${each.value.source_path}.zip") : data.archive_file.lambda_inline.output_base64sha256

  runtime = var.lambda_runtime
  handler = var.lambda_handler

  memory_size = each.value.memory_size
  timeout     = each.value.timeout

  environment {
    variables = merge({
      FUNCTION_NAME = each.value.name
      SNS_TOPIC_ARN = aws_sns_topic.main.arn
    }, each.value.env_vars)
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
    Name     = "${local.name_prefix}-${each.value.name}"
    Function = each.value.name
  })
}

# Lambda CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = { for idx, func in var.lambda_functions : func.name => func }

  name              = "/aws/lambda/${local.name_prefix}-${each.value.name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.value.name}-logs"
  })
}

# Lambda permissions for SNS
resource "aws_lambda_permission" "sns" {
  for_each = { for idx, func in var.lambda_functions : func.name => func }

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main[each.key].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.main.arn
}
