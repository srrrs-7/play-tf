# =============================================================================
# Lambda Function
# =============================================================================

# Inline Lambda code (used when lambda_source_path is not provided)
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
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def handler(event, context):
    print(f"Event: {json.dumps(event)}")

    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')

    try:
        if http_method == 'GET':
            if event.get('pathParameters') and event['pathParameters'].get('id'):
                # Get single item
                item_id = event['pathParameters']['id']
                response = table.get_item(Key={'id': item_id})
                if 'Item' in response:
                    return build_response(200, response['Item'])
                else:
                    return build_response(404, {'error': 'Item not found'})
            else:
                # List all items
                response = table.scan()
                return build_response(200, {'items': response.get('Items', [])})

        elif http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            if 'id' not in body:
                body['id'] = str(uuid.uuid4())
            table.put_item(Item=body)
            return build_response(201, body)

        elif http_method == 'PUT':
            if not event.get('pathParameters') or not event['pathParameters'].get('id'):
                return build_response(400, {'error': 'Missing id parameter'})

            item_id = event['pathParameters']['id']
            body = json.loads(event.get('body', '{}'))
            body['id'] = item_id
            table.put_item(Item=body)
            return build_response(200, body)

        elif http_method == 'DELETE':
            if not event.get('pathParameters') or not event['pathParameters'].get('id'):
                return build_response(400, {'error': 'Missing id parameter'})

            item_id = event['pathParameters']['id']
            table.delete_item(Key={'id': item_id})
            return build_response(204, None)

        else:
            return build_response(405, {'error': 'Method not allowed'})

    except Exception as e:
        print(f"Error: {str(e)}")
        return build_response(500, {'error': str(e)})

def build_response(status_code, body):
    response = {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }
    }
    if body is not None:
        response['body'] = json.dumps(body, default=decimal_default)
    return response
PYTHON
    filename = "index.py"
  }
}

# External Lambda source (when lambda_source_path is provided)
data "archive_file" "lambda_external" {
  count = var.lambda_source_path != null ? 1 : 0

  type        = "zip"
  source_dir  = var.lambda_source_path
  output_path = "${path.module}/.terraform/lambda_external.zip"
}

# Lambda function
resource "aws_lambda_function" "main" {
  function_name = local.name_prefix
  description   = "Lambda function for API Gateway - DynamoDB integration"
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

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
