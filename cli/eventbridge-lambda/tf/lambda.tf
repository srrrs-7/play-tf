# =============================================================================
# Lambda Function
# =============================================================================

# デフォルトのLambdaコード
locals {
  default_lambda_code = <<-EOF
    exports.handler = async (event) => {
        console.log('EventBridge event received:', JSON.stringify(event, null, 2));

        const {
            source,
            'detail-type': detailType,
            detail,
            time,
            id
        } = event;

        console.log('Event details:', {
            eventId: id,
            source,
            detailType,
            time,
            detail
        });

        // Process based on event type
        switch (detailType) {
            case 'OrderCreated':
                console.log('Processing new order:', detail);
                break;
            case 'UserSignedUp':
                console.log('Processing new user signup:', detail);
                break;
            case 'PaymentProcessed':
                console.log('Processing payment:', detail);
                break;
            default:
                console.log('Processing generic event:', detail);
        }

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Event processed successfully',
                eventId: id
            })
        };
    };
  EOF
}

# インラインコード用のアーカイブ
data "archive_file" "lambda_default" {
  count       = var.lambda_source_path == null ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_default.zip"

  source {
    content  = local.default_lambda_code
    filename = "index.js"
  }
}

# カスタムソースコード用のアーカイブ
data "archive_file" "lambda_custom" {
  count       = var.lambda_source_path != null ? 1 : 0
  type        = "zip"
  source_dir  = var.lambda_source_path
  output_path = "${path.module}/lambda_custom.zip"
}

resource "aws_lambda_function" "handler" {
  function_name = "${var.stack_name}-handler"
  role          = aws_iam_role.lambda.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = var.lambda_source_path == null ? data.archive_file.lambda_default[0].output_path : data.archive_file.lambda_custom[0].output_path
  source_code_hash = var.lambda_source_path == null ? data.archive_file.lambda_default[0].output_base64sha256 : data.archive_file.lambda_custom[0].output_base64sha256

  environment {
    variables = merge(
      {
        ENVIRONMENT = var.environment
        STACK_NAME  = var.stack_name
      },
      var.lambda_environment_variables
    )
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-handler"
  })
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.stack_name}-handler"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-logs"
  })
}
