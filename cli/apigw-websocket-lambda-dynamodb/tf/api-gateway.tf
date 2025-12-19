# =============================================================================
# API Gateway WebSocket API
# =============================================================================

resource "aws_apigatewayv2_api" "main" {
  name                       = local.name_prefix
  protocol_type              = "WEBSOCKET"
  route_selection_expression = var.route_selection_expression

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

# =============================================================================
# Routes and Integrations
# =============================================================================

# $connect route
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_integration" "connect" {
  api_id                    = aws_apigatewayv2_api.main.id
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.connect.invoke_arn
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# $disconnect route
resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect.id}"
}

resource "aws_apigatewayv2_integration" "disconnect" {
  api_id                    = aws_apigatewayv2_api.main.id
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.disconnect.invoke_arn
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# $default route (handles all other messages)
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.message.id}"
}

resource "aws_apigatewayv2_integration" "message" {
  api_id                    = aws_apigatewayv2_api.main.id
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.message.invoke_arn
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# sendMessage route (custom action)
resource "aws_apigatewayv2_route" "send_message" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "sendMessage"
  target    = "integrations/${aws_apigatewayv2_integration.message.id}"
}

# =============================================================================
# Stage
# =============================================================================

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.stage_name
  auto_deploy = true

  default_route_settings {
    logging_level            = "INFO"
    throttling_burst_limit   = 5000
    throttling_rate_limit    = 10000
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.stage_name}"
  })
}
