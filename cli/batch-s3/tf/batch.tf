# =============================================================================
# AWS Batch Compute Environment
# =============================================================================

resource "aws_batch_compute_environment" "main" {
  type  = "MANAGED"
  state = "ENABLED"

  compute_resources {
    type      = var.compute_type
    max_vcpus = var.max_vcpus

    subnets            = aws_subnet.main[*].id
    security_group_ids = [aws_security_group.batch.id]
  }

  service_role = aws_iam_role.batch_service.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-compute-env"
  })

  depends_on = [aws_iam_role_policy_attachment.batch_service]
}

# =============================================================================
# AWS Batch Job Queue
# =============================================================================

resource "aws_batch_job_queue" "main" {
  name     = local.name_prefix
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.main.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-job-queue"
  })
}

# =============================================================================
# AWS Batch Job Definition
# =============================================================================

resource "aws_batch_job_definition" "main" {
  name = local.name_prefix
  type = "container"

  platform_capabilities = [
    var.compute_type == "EC2" || var.compute_type == "SPOT" ? "EC2" : "FARGATE"
  ]

  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }

  retry_strategy {
    attempts = var.job_retry_attempts
  }

  container_properties = jsonencode({
    image = var.container_image

    resourceRequirements = [
      {
        type  = "VCPU"
        value = tostring(var.job_vcpus)
      },
      {
        type  = "MEMORY"
        value = tostring(var.job_memory)
      }
    ]

    command = var.job_command

    environment = var.create_s3_buckets ? [
      {
        name  = "INPUT_BUCKET"
        value = aws_s3_bucket.input[0].id
      },
      {
        name  = "OUTPUT_BUCKET"
        value = aws_s3_bucket.output[0].id
      }
    ] : []

    executionRoleArn = aws_iam_role.batch_execution.arn
    jobRoleArn       = aws_iam_role.batch_job.arn

    fargatePlatformConfiguration = var.compute_type == "FARGATE" || var.compute_type == "FARGATE_SPOT" ? {
      platformVersion = "LATEST"
    } : null

    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "batch"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-job-definition"
  })
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/batch/${local.name_prefix}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-logs"
  })
}
