# =============================================================================
# Lambda Function (Container Image)
# =============================================================================

resource "aws_lambda_function" "main" {
  count = var.create_lambda_function ? 1 : 0

  function_name = var.stack_name
  role          = aws_iam_role.lambda_execution.arn
  package_type  = "Image"
  image_uri     = var.container_image_uri != null ? var.container_image_uri : "${aws_ecr_repository.main.repository_url}:${var.container_image_tag}"

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout
  architectures = [var.lambda_architecture]

  # Reserved concurrency (-1 means no limit)
  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : null

  # Environment variables
  dynamic "environment" {
    for_each = length(var.lambda_environment_variables) > 0 ? [1] : []
    content {
      variables = var.lambda_environment_variables
    }
  }

  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = var.enable_vpc && length(var.vpc_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  # X-Ray tracing
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_ecr,
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-lambda"
  })

  lifecycle {
    # Ignore image_uri changes to allow external updates
    ignore_changes = [image_uri]
  }
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-lambda-logs"
  })
}

# =============================================================================
# Lambda Function URL (Optional - simpler alternative to API Gateway)
# =============================================================================

resource "aws_lambda_function_url" "main" {
  count = var.create_lambda_function && var.create_api_gateway ? 0 : (var.create_lambda_function ? 1 : 0)

  function_name      = aws_lambda_function.main[0].function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["*"]
    allow_origins     = ["*"]
    expose_headers    = []
    max_age           = 86400
  }
}
