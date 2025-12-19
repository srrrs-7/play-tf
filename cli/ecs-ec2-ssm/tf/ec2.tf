# =============================================================================
# Launch Template
# =============================================================================
# ECS-optimized AMIを使用したEC2インスタンス起動テンプレート

resource "aws_launch_template" "ecs" {
  name = "${local.name_prefix}-lt"

  image_id      = local.ecs_ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
    delete_on_termination       = true
  }

  # ECSクラスターへの登録設定
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${var.stack_name} >> /etc/ecs/ecs.config
    EOF
  )

  # メタデータオプション（IMDSv2推奨）
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # EBSボリューム設定
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, var.tags, {
      Name       = "${local.name_prefix}-instance"
      ECSCluster = var.stack_name
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, var.tags, {
      Name = "${local.name_prefix}-volume"
    })
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-lt"
  })
}

# =============================================================================
# Auto Scaling Group
# =============================================================================

resource "aws_autoscaling_group" "ecs" {
  name = "${local.name_prefix}-asg"

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  vpc_zone_identifier = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  # ヘルスチェック設定
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # インスタンスリフレッシュ設定
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # タグ
  dynamic "tag" {
    for_each = merge(local.common_tags, var.tags, {
      Name       = "${local.name_prefix}-instance"
      ECSCluster = var.stack_name
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# ECS Capacity Provider
# =============================================================================
# Auto Scaling GroupをECSのキャパシティプロバイダーとして登録

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${local.name_prefix}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn

    managed_scaling {
      status                    = var.enable_managed_scaling ? "ENABLED" : "DISABLED"
      target_capacity           = var.target_capacity_percent
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 10
    }

    managed_termination_protection = "DISABLED"
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-cp"
  })
}
