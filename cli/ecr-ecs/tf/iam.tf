# =============================================================================
# ECS Task Execution Role
# =============================================================================
# ECS TasksがECRからイメージをプルし、CloudWatch Logsに書き込むための権限

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecs-task-execution"
  })
}

# Attach AmazonECSTaskExecutionRolePolicy
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# ECS Task Role (for application)
# =============================================================================
# アプリケーションコンテナがAWSサービスにアクセスするための権限（オプション）

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecs-task"
  })
}

# =============================================================================
# CloudWatch Logs Policy for Task Execution Role
# =============================================================================
# CloudWatch Logsグループの作成権限を追加

resource "aws_iam_role_policy" "ecs_task_execution_logs" {
  name = "${local.name_prefix}-logs-policy"
  role = aws_iam_role.ecs_task_execution.id

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
        Resource = "*"
      }
    ]
  })
}
