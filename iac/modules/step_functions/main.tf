resource "aws_sfn_state_machine" "this" {
  name     = var.name
  role_arn = var.role_arn != null ? var.role_arn : aws_iam_role.this[0].arn

  definition = var.definition

  type = var.type

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    include_execution_data = var.logging_configuration.include_execution_data
    level                  = var.logging_configuration.level
  }

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  tags = var.tags

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy_attachment.sfn_logging
  ]
}

# CloudWatch Logs Group
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# IAM Role (Optional: Created if role_arn is not provided)
resource "aws_iam_role" "this" {
  count = var.role_arn == null ? 1 : 0

  name = "${var.name}-role"

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

  tags = var.tags
}

# Basic Logging Policy for generated role
resource "aws_iam_role_policy_attachment" "sfn_logging" {
  count = var.role_arn == null ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess" # Note: In production, scope this down
}

# Custom Policy for generated role
resource "aws_iam_role_policy" "custom" {
  count = var.role_arn == null && length(var.policy_statements) > 0 ? 1 : 0

  name = "${var.name}-custom-policy"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.policy_statements
  })
}
