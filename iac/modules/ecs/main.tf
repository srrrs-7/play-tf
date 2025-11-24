locals {
  cluster_name = var.create_cluster ? aws_ecs_cluster.this[0].name : var.cluster_name
  cluster_id   = var.create_cluster ? aws_ecs_cluster.this[0].id : var.cluster_id
}

resource "aws_ecs_cluster" "this" {
  count = var.create_cluster ? 1 : 0
  name  = var.cluster_name != null ? var.cluster_name : "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  count             = var.create_log_group ? 1 : 0
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  container_definitions    = var.container_definitions
  requires_compatibilities = var.requires_compatibilities
  network_mode             = var.network_mode
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = var.operating_system_family
    cpu_architecture        = var.cpu_architecture
  }

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = local.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = length(var.capacity_provider_strategy) == 0 ? "FARGATE" : null

  dynamic "network_configuration" {
    for_each = var.network_mode == "awsvpc" ? [1] : []
    content {
      subnets          = var.subnet_ids
      security_groups  = var.security_group_ids
      assign_public_ip = var.assign_public_ip
    }
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = lookup(capacity_provider_strategy.value, "base", null)
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}
