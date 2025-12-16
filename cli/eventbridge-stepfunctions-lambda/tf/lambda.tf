# =============================================================================
# Lambda Functions
# =============================================================================

# デフォルトのLambdaコード
locals {
  lambda_codes = {
    validate = <<-EOF
      exports.handler = async (event) => {
          console.log('Validating order:', JSON.stringify(event));
          const { orderId, items } = event;

          if (!orderId || !items || items.length === 0) {
              throw new Error('Invalid order: missing required fields');
          }

          const totalAmount = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);

          return {
              ...event,
              validated: true,
              totalAmount,
              validatedAt: new Date().toISOString()
          };
      };
    EOF

    payment = <<-EOF
      exports.handler = async (event) => {
          console.log('Processing payment:', JSON.stringify(event));
          const { orderId, totalAmount } = event;

          // Simulate payment processing
          const paymentId = 'PAY-' + Math.random().toString(36).substring(2, 15);

          return {
              ...event,
              paymentId,
              paymentStatus: 'completed',
              processedAt: new Date().toISOString()
          };
      };
    EOF

    shipping = <<-EOF
      exports.handler = async (event) => {
          console.log('Creating shipping:', JSON.stringify(event));
          const { orderId } = event;

          // Simulate shipping creation
          const trackingNumber = 'TRK-' + Math.random().toString(36).substring(2, 15).toUpperCase();

          return {
              ...event,
              trackingNumber,
              shippingStatus: 'created',
              estimatedDelivery: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
          };
      };
    EOF

    notify = <<-EOF
      exports.handler = async (event) => {
          console.log('Sending notification:', JSON.stringify(event));
          const { orderId, trackingNumber, paymentId } = event;

          console.log('Notification details:', {
              orderId,
              trackingNumber,
              paymentId,
              message: 'Your order has been processed successfully!'
          });

          return {
              ...event,
              notificationSent: true,
              notifiedAt: new Date().toISOString()
          };
      };
    EOF
  }
}

# Lambda用アーカイブ
data "archive_file" "lambda" {
  for_each    = toset(local.lambda_functions)
  type        = "zip"
  output_path = "${path.module}/lambda_${each.key}.zip"

  source {
    content  = local.lambda_codes[each.key]
    filename = "index.js"
  }
}

# Lambda関数
resource "aws_lambda_function" "functions" {
  for_each = toset(local.lambda_functions)

  function_name = "${var.stack_name}-${each.key}"
  role          = aws_iam_role.lambda[each.key].arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      STACK_NAME  = var.stack_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(local.common_tags, var.tags, {
    Name     = "${local.name_prefix}-${each.key}"
    Function = each.key
  })
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = toset(local.lambda_functions)

  name              = "/aws/lambda/${var.stack_name}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-${each.key}-logs"
  })
}
