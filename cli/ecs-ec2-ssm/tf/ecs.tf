# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = var.stack_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

# =============================================================================
# ECS Cluster Capacity Provider Association
# =============================================================================

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }
}

# =============================================================================
# ECS Task Definition (EC2)
# =============================================================================

resource "aws_ecs_task_definition" "main" {
  family                   = var.stack_name
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = var.stack_name
      image     = var.container_image
      essential = true
      cpu       = var.container_cpu
      memory    = var.container_memory

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0 # Dynamic port mapping for EC2
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-task"
  })
}

# =============================================================================
# ECS Service
# =============================================================================

resource "aws_ecs_service" "main" {
  count = var.create_ecs_service ? 1 : 0

  name            = "${var.stack_name}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

  # ECS Execを有効化（コンテナへの直接アクセス）
  enable_execute_command = var.enable_execute_command

  # EC2起動タイプを使用
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }

  # デプロイ設定
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # Circuit breaker
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # 配置戦略（AZ分散）
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
}
