# =============================================================================
# API Gateway HTTP API (Optional)
# =============================================================================

resource "aws_apigatewayv2_api" "main" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "HTTP API for ${var.stack_name} Lambda function"

  cors_configuration {
    allow_headers = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 86400
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-api"
  })
}

# =============================================================================
# API Gateway Stage
# =============================================================================

resource "aws_apigatewayv2_stage" "main" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  api_id      = aws_apigatewayv2_api.main[0].id
  name        = var.api_gateway_stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
      integrationError  = "$context.integrationErrorMessage"
      integrationLatency = "$context.integrationLatency"
    })
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-stage"
  })
}

# =============================================================================
# API Gateway Integration
# =============================================================================

resource "aws_apigatewayv2_integration" "main" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  api_id                 = aws_apigatewayv2_api.main[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.main[0].invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# =============================================================================
# API Gateway Routes
# =============================================================================

resource "aws_apigatewayv2_route" "default" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  api_id    = aws_apigatewayv2_api.main[0].id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.main[0].id}"
}

resource "aws_apigatewayv2_route" "any" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  api_id    = aws_apigatewayv2_api.main[0].id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.main[0].id}"
}

# =============================================================================
# Lambda Permission for API Gateway
# =============================================================================

resource "aws_lambda_permission" "api_gateway" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main[0].execution_arn}/*/*"
}

# =============================================================================
# CloudWatch Log Group for API Gateway
# =============================================================================

resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.create_api_gateway && var.create_lambda_function ? 1 : 0

  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-api-logs"
  })
}
