# =============================================================================
# Lambda Execution Roles
# =============================================================================

resource "aws_iam_role" "lambda" {
  for_each = toset(local.lambda_functions)

  name = "${local.name_prefix}-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-${each.key}-role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  for_each = toset(local.lambda_functions)

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# Step Functions Execution Role
# =============================================================================

resource "aws_iam_role" "stepfunctions" {
  name = "${local.name_prefix}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-sfn-role"
  })
}

# Step FunctionsがLambdaを呼び出す権限
resource "aws_iam_role_policy" "stepfunctions_invoke_lambda" {
  name = "${local.name_prefix}-sfn-invoke-lambda"
  role = aws_iam_role.stepfunctions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [for func in local.lambda_functions : aws_lambda_function.functions[func].arn]
      }
    ]
  })
}

# Step FunctionsがCloudWatch Logsに書き込む権限
resource "aws_iam_role_policy" "stepfunctions_logs" {
  name = "${local.name_prefix}-sfn-logs"
  role = aws_iam_role.stepfunctions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# EventBridge Role (to start Step Functions)
# =============================================================================

resource "aws_iam_role" "eventbridge" {
  name = "${local.name_prefix}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-eventbridge-role"
  })
}

# EventBridgeがStep Functionsを開始する権限
resource "aws_iam_role_policy" "eventbridge_start_sfn" {
  name = "${local.name_prefix}-eb-start-sfn"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = [
          aws_sfn_state_machine.order_workflow.arn
        ]
      }
    ]
  })
}
