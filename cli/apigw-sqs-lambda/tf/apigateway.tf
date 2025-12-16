# =============================================================================
# API Gateway IAM Role
# =============================================================================
# API GatewayがSQSにメッセージを送信するためのIAMロール

# Trust Policy
data "aws_iam_policy_document" "apigw_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# SQS送信ポリシー
data "aws_iam_policy_document" "apigw_sqs" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main.arn]
  }
}

# IAM Role
resource "aws_iam_role" "apigw" {
  name               = "${local.name_prefix}-apigw-sqs-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume_role.json
  description        = "IAM Role for API Gateway to send messages to SQS"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-apigw-sqs-role"
  })
}

# Inline Policy
resource "aws_iam_role_policy" "apigw_sqs" {
  name   = "sqs-send"
  role   = aws_iam_role.apigw.id
  policy = data.aws_iam_policy_document.apigw_sqs.json
}

# =============================================================================
# API Gateway REST API
# =============================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = local.name_prefix
  description = "API Gateway for async message processing via SQS"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, var.tags, {
    Name = local.name_prefix
  })
}

# =============================================================================
# API Gateway Resource (/messages)
# =============================================================================

resource "aws_api_gateway_resource" "messages" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = var.api_endpoint_path
}

# =============================================================================
# POST Method - SQS Integration
# =============================================================================

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.messages.id
  http_method   = "POST"
  authorization = "NONE"
}

# SQS Integration
resource "aws_api_gateway_integration" "sqs" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.messages.id
  http_method             = aws_api_gateway_method.post.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${local.region}:sqs:path/${local.account_id}/${aws_sqs_queue.main.name}"
  credentials             = aws_iam_role.apigw.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  # リクエストボディをSQSメッセージに変換
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

# Method Response
resource "aws_api_gateway_method_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = var.enable_cors ? {
    "method.response.header.Access-Control-Allow-Origin" = true
  } : {}
}

# Integration Response
resource "aws_api_gateway_integration_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = aws_api_gateway_method_response.post_200.status_code

  # SQSレスポンスからメッセージIDを抽出してレスポンス
  response_templates = {
    "application/json" = <<-EOF
      {
        "message": "Message sent to queue",
        "messageId": "$input.path('$.SendMessageResponse.SendMessageResult.MessageId')"
      }
    EOF
  }

  response_parameters = var.enable_cors ? {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.cors_allowed_origins}'"
  } : {}

  depends_on = [aws_api_gateway_integration.sqs]
}

# =============================================================================
# CORS - OPTIONS Method
# =============================================================================

resource "aws_api_gateway_method" "options" {
  count         = var.enable_cors ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.messages.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.options[0].http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.options[0].http_method
  status_code = aws_api_gateway_method_response.options_200[0].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allowed_origins}'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# =============================================================================
# API Gateway Deployment
# =============================================================================

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  # 設定変更時に再デプロイするためのトリガー
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.messages.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.sqs.id,
      var.enable_cors ? aws_api_gateway_method.options[0].id : "",
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.post,
    aws_api_gateway_integration.sqs,
    aws_api_gateway_integration_response.post_200,
  ]
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.api_stage_name

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-${var.api_stage_name}"
  })
}
