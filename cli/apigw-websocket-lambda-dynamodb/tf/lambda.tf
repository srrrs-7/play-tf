# =============================================================================
# Lambda Functions
# =============================================================================

# Inline Lambda code
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/.terraform/lambda.zip"

  source {
    content  = <<-PYTHON
import json
import boto3
import os
import time

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])
TTL_HOURS = int(os.environ.get('TTL_HOURS', '24'))

def get_apigw_management_client(event):
    domain = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    endpoint_url = f"https://{domain}/{stage}"
    return boto3.client('apigatewaymanagementapi', endpoint_url=endpoint_url)

def connect_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    ttl = int(time.time()) + (TTL_HOURS * 3600)

    table.put_item(Item={
        'connectionId': connection_id,
        'connectedAt': event['requestContext'].get('connectedAt', int(time.time() * 1000)),
        'ttl': ttl
    })

    print(f"Connected: {connection_id}")
    return {'statusCode': 200, 'body': 'Connected'}

def disconnect_handler(event, context):
    connection_id = event['requestContext']['connectionId']

    table.delete_item(Key={'connectionId': connection_id})

    print(f"Disconnected: {connection_id}")
    return {'statusCode': 200, 'body': 'Disconnected'}

def message_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    body = json.loads(event.get('body', '{}'))
    action = body.get('action', 'default')
    message = body.get('message', '')

    print(f"Message from {connection_id}: action={action}, message={message}")

    if action == 'sendMessage':
        broadcast_message(event, {
            'type': 'message',
            'from': connection_id,
            'message': message
        })
    else:
        send_to_connection(event, connection_id, {
            'type': 'echo',
            'message': message or 'Hello! Send {"action": "sendMessage", "message": "your message"} to broadcast.'
        })

    return {'statusCode': 200, 'body': 'Message processed'}

def send_to_connection(event, connection_id, data):
    client = get_apigw_management_client(event)
    try:
        client.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(data).encode('utf-8')
        )
    except client.exceptions.GoneException:
        print(f"Connection {connection_id} is gone, removing from table")
        table.delete_item(Key={'connectionId': connection_id})

def broadcast_message(event, data):
    connections = table.scan(ProjectionExpression='connectionId')
    client = get_apigw_management_client(event)

    for item in connections.get('Items', []):
        conn_id = item['connectionId']
        try:
            client.post_to_connection(
                ConnectionId=conn_id,
                Data=json.dumps(data).encode('utf-8')
            )
        except client.exceptions.GoneException:
            print(f"Connection {conn_id} is gone, removing from table")
            table.delete_item(Key={'connectionId': conn_id})

def handler(event, context):
    route_key = event['requestContext'].get('routeKey', '$default')

    if route_key == '$connect':
        return connect_handler(event, context)
    elif route_key == '$disconnect':
        return disconnect_handler(event, context)
    else:
        return message_handler(event, context)
PYTHON
    filename = "index.py"
  }
}

# Connect Lambda
resource "aws_lambda_function" "connect" {
  function_name = "${local.name_prefix}-connect"
  description   = "WebSocket connect handler"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = var.lambda_runtime
  handler = "index.connect_handler"

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      TTL_HOURS         = var.connection_ttl_hours
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.connect]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-connect"
  })
}

# Disconnect Lambda
resource "aws_lambda_function" "disconnect" {
  function_name = "${local.name_prefix}-disconnect"
  description   = "WebSocket disconnect handler"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = var.lambda_runtime
  handler = "index.disconnect_handler"

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      TTL_HOURS         = var.connection_ttl_hours
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.disconnect]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-disconnect"
  })
}

# Message Lambda
resource "aws_lambda_function" "message" {
  function_name = "${local.name_prefix}-message"
  description   = "WebSocket message handler"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = var.lambda_runtime
  handler = "index.message_handler"

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      TTL_HOURS         = var.connection_ttl_hours
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.message]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-message"
  })
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "connect" {
  name              = "/aws/lambda/${local.name_prefix}-connect"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-connect-logs"
  })
}

resource "aws_cloudwatch_log_group" "disconnect" {
  name              = "/aws/lambda/${local.name_prefix}-disconnect"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-disconnect-logs"
  })
}

resource "aws_cloudwatch_log_group" "message" {
  name              = "/aws/lambda/${local.name_prefix}-message"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-message-logs"
  })
}

# =============================================================================
# Lambda Permissions
# =============================================================================

resource "aws_lambda_permission" "connect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "disconnect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "message" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
