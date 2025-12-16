# =============================================================================
# Lambda Execution Role
# =============================================================================

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

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
    Name = "${local.name_prefix}-lambda-role"
  })
}

# =============================================================================
# Lambda Basic Execution Policy
# =============================================================================

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# Additional Lambda Permissions (Optional)
# =============================================================================
# 必要に応じて追加の権限を付与

resource "aws_iam_role_policy" "lambda_additional" {
  count = length(var.lambda_environment_variables) > 0 ? 1 : 0
  name  = "${local.name_prefix}-lambda-additional"
  role  = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
