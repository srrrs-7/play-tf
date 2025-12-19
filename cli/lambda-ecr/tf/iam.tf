# =============================================================================
# Lambda Execution Role
# =============================================================================

resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution"

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
    Name = "${local.name_prefix}-lambda-execution"
  })
}

# =============================================================================
# Attach Basic Execution Role Policy
# =============================================================================

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# ECR Access Policy
# =============================================================================

resource "aws_iam_role_policy" "lambda_ecr" {
  name = "${local.name_prefix}-ecr-access"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = aws_ecr_repository.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# VPC Access Policy (Conditional)
# =============================================================================

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count = var.enable_vpc ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# =============================================================================
# X-Ray Tracing Policy (Conditional)
# =============================================================================

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.enable_xray_tracing ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# =============================================================================
# CloudWatch Logs Policy (Enhanced)
# =============================================================================

resource "aws_iam_role_policy" "lambda_logs" {
  name = "${local.name_prefix}-logs-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.lambda.arn,
          "${aws_cloudwatch_log_group.lambda.arn}:*"
        ]
      }
    ]
  })
}
