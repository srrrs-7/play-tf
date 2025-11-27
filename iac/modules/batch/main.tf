# Batch Compute Environment
resource "aws_batch_compute_environment" "this" {
  for_each = { for env in var.compute_environments : env.name => env }

  compute_environment_name = each.value.name
  type                     = lookup(each.value, "type", "MANAGED")
  state                    = lookup(each.value, "state", "ENABLED")
  service_role             = lookup(each.value, "service_role", null)

  # コンピュートリソース設定（MANAGEDタイプの場合）
  dynamic "compute_resources" {
    for_each = lookup(each.value, "type", "MANAGED") == "MANAGED" ? [each.value.compute_resources] : []
    content {
      type                = compute_resources.value.type
      allocation_strategy = lookup(compute_resources.value, "allocation_strategy", null)
      max_vcpus           = compute_resources.value.max_vcpus
      min_vcpus           = lookup(compute_resources.value, "min_vcpus", 0)
      desired_vcpus       = lookup(compute_resources.value, "desired_vcpus", null)

      # EC2/SPOT設定
      instance_type         = lookup(compute_resources.value, "instance_type", null)
      instance_role         = lookup(compute_resources.value, "instance_role", null)
      image_id              = lookup(compute_resources.value, "image_id", null)
      ec2_key_pair          = lookup(compute_resources.value, "ec2_key_pair", null)
      bid_percentage        = lookup(compute_resources.value, "bid_percentage", null)
      spot_iam_fleet_role   = lookup(compute_resources.value, "spot_iam_fleet_role", null)
      placement_group       = lookup(compute_resources.value, "placement_group", null)

      # ネットワーク設定
      subnets         = compute_resources.value.subnets
      security_group_ids = compute_resources.value.security_group_ids

      # EC2設定
      dynamic "ec2_configuration" {
        for_each = lookup(compute_resources.value, "ec2_configuration", null) != null ? [compute_resources.value.ec2_configuration] : []
        content {
          image_id_override = lookup(ec2_configuration.value, "image_id_override", null)
          image_type        = lookup(ec2_configuration.value, "image_type", null)
        }
      }

      # 起動テンプレート
      dynamic "launch_template" {
        for_each = lookup(compute_resources.value, "launch_template", null) != null ? [compute_resources.value.launch_template] : []
        content {
          launch_template_id   = lookup(launch_template.value, "launch_template_id", null)
          launch_template_name = lookup(launch_template.value, "launch_template_name", null)
          version              = lookup(launch_template.value, "version", null)
        }
      }

      tags = var.tags
    }
  }

  # EKS設定
  dynamic "eks_configuration" {
    for_each = lookup(each.value, "eks_configuration", null) != null ? [each.value.eks_configuration] : []
    content {
      eks_cluster_arn    = eks_configuration.value.eks_cluster_arn
      kubernetes_namespace = eks_configuration.value.kubernetes_namespace
    }
  }

  # 更新ポリシー
  dynamic "update_policy" {
    for_each = lookup(each.value, "update_policy", null) != null ? [each.value.update_policy] : []
    content {
      job_execution_timeout_minutes = update_policy.value.job_execution_timeout_minutes
      terminate_jobs_on_update      = update_policy.value.terminate_jobs_on_update
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Batch Job Queue
resource "aws_batch_job_queue" "this" {
  for_each = { for queue in var.job_queues : queue.name => queue }

  name                  = each.value.name
  state                 = lookup(each.value, "state", "ENABLED")
  priority              = each.value.priority
  scheduling_policy_arn = lookup(each.value, "scheduling_policy_arn", null)

  # コンピュート環境の順序
  dynamic "compute_environment_order" {
    for_each = each.value.compute_environments
    content {
      order               = compute_environment_order.value.order
      compute_environment = lookup(compute_environment_order.value, "compute_environment_arn", null) != null ? compute_environment_order.value.compute_environment_arn : aws_batch_compute_environment.this[compute_environment_order.value.compute_environment_name].arn
    }
  }

  tags = var.tags

  depends_on = [aws_batch_compute_environment.this]
}

# Batch Job Definition
resource "aws_batch_job_definition" "this" {
  for_each = { for job in var.job_definitions : job.name => job }

  name                  = each.value.name
  type                  = lookup(each.value, "type", "container")
  platform_capabilities = lookup(each.value, "platform_capabilities", ["EC2"])
  propagate_tags        = lookup(each.value, "propagate_tags", false)

  # コンテナプロパティ（containerタイプの場合）
  container_properties = lookup(each.value, "container_properties", null)

  # EKSプロパティ
  eks_properties = lookup(each.value, "eks_properties", null)

  # ノードプロパティ（multinode並列ジョブの場合）
  node_properties = lookup(each.value, "node_properties", null)

  # パラメータ
  parameters = lookup(each.value, "parameters", null)

  # リトライ戦略
  dynamic "retry_strategy" {
    for_each = lookup(each.value, "retry_strategy", null) != null ? [each.value.retry_strategy] : []
    content {
      attempts = lookup(retry_strategy.value, "attempts", 1)

      dynamic "evaluate_on_exit" {
        for_each = lookup(retry_strategy.value, "evaluate_on_exit", [])
        content {
          action           = evaluate_on_exit.value.action
          on_exit_code     = lookup(evaluate_on_exit.value, "on_exit_code", null)
          on_reason        = lookup(evaluate_on_exit.value, "on_reason", null)
          on_status_reason = lookup(evaluate_on_exit.value, "on_status_reason", null)
        }
      }
    }
  }

  # タイムアウト
  dynamic "timeout" {
    for_each = lookup(each.value, "timeout_seconds", null) != null ? [1] : []
    content {
      attempt_duration_seconds = each.value.timeout_seconds
    }
  }

  # スケジューリング優先度
  scheduling_priority = lookup(each.value, "scheduling_priority", null)

  tags = var.tags
}

# Batch Scheduling Policy
resource "aws_batch_scheduling_policy" "this" {
  for_each = { for policy in var.scheduling_policies : policy.name => policy }

  name = each.value.name

  fair_share_policy {
    compute_reservation = lookup(each.value, "compute_reservation", null)
    share_decay_seconds = lookup(each.value, "share_decay_seconds", null)

    dynamic "share_distribution" {
      for_each = lookup(each.value, "share_distribution", [])
      content {
        share_identifier = share_distribution.value.share_identifier
        weight_factor    = lookup(share_distribution.value, "weight_factor", null)
      }
    }
  }

  tags = var.tags
}
