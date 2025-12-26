# =============================================================================
# SageMaker Resources
# =============================================================================

# =============================================================================
# SageMaker Notebook Instance
# =============================================================================

resource "aws_sagemaker_notebook_instance" "main" {
  count = var.create_notebook ? 1 : 0

  name                   = "${var.stack_name}-notebook"
  instance_type          = var.notebook_instance_type
  role_arn               = local.sagemaker_role_arn
  volume_size            = var.notebook_volume_size
  platform_identifier    = var.notebook_platform_identifier
  direct_internet_access = var.notebook_direct_internet_access
  lifecycle_config_name  = var.notebook_lifecycle_config_name

  # VPC settings (optional)
  subnet_id       = var.create_domain && length(var.subnet_ids) > 0 ? var.subnet_ids[0] : null
  security_groups = var.create_domain && var.vpc_id != null ? [aws_security_group.sagemaker[0].id] : null

  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-notebook"
  })

  depends_on = [
    aws_iam_role.sagemaker_execution
  ]
}

# =============================================================================
# SageMaker Experiment
# =============================================================================

resource "aws_sagemaker_mlflow_tracking_server" "main" {
  count = false ? 1 : 0 # Disabled by default - requires additional setup

  tracking_server_name = "${var.stack_name}-mlflow"
  role_arn             = local.sagemaker_role_arn
  artifact_store_uri   = var.create_s3_buckets ? "s3://${aws_s3_bucket.model[0].id}/mlflow" : null
}

# =============================================================================
# SageMaker Model Package Group (Model Registry)
# =============================================================================

resource "aws_sagemaker_model_package_group" "main" {
  count = var.create_model_package_group ? 1 : 0

  model_package_group_name        = var.stack_name
  model_package_group_description = coalesce(var.model_package_group_description, "Model package group for ${var.stack_name}")

  tags = merge(local.common_tags, {
    Name = var.stack_name
  })
}

# =============================================================================
# SageMaker Domain (for Studio) - Optional
# =============================================================================

resource "aws_sagemaker_domain" "main" {
  count = var.create_domain && var.vpc_id != null ? 1 : 0

  domain_name = var.stack_name
  auth_mode   = var.domain_auth_mode
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  default_user_settings {
    execution_role = local.sagemaker_role_arn

    sharing_settings {
      notebook_output_option = "Allowed"
      s3_output_path         = var.create_s3_buckets ? "s3://${aws_s3_bucket.output[0].id}/studio/" : null
    }
  }

  tags = merge(local.common_tags, {
    Name = var.stack_name
  })

  depends_on = [
    aws_iam_role.sagemaker_execution
  ]
}

# Security group for SageMaker (when using VPC)
resource "aws_security_group" "sagemaker" {
  count = var.create_domain && var.vpc_id != null ? 1 : 0

  name        = "${var.stack_name}-sagemaker-sg"
  description = "Security group for SageMaker resources"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow all traffic from within the security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-sagemaker-sg"
  })
}

# =============================================================================
# SageMaker Notebook Lifecycle Configuration (Optional)
# =============================================================================

resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "main" {
  count = var.create_notebook ? 1 : 0

  name = "${var.stack_name}-lifecycle"

  on_create = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Install common ML libraries
    sudo -u ec2-user -i <<'INNEREOF'
    source /home/ec2-user/anaconda3/bin/activate python3
    pip install --upgrade pip
    pip install boto3 pandas numpy scikit-learn matplotlib seaborn
    conda deactivate
    INNEREOF

    echo "On-create script completed"
  EOF
  )

  on_start = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Configure git
    sudo -u ec2-user -i <<'INNEREOF'
    git config --global credential.helper '!aws codecommit credential-helper $@'
    git config --global credential.UseHttpPath true
    INNEREOF

    echo "On-start script completed"
  EOF
  )
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "training" {
  name              = "/aws/sagemaker/TrainingJobs/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-training-logs"
  })
}

resource "aws_cloudwatch_log_group" "processing" {
  name              = "/aws/sagemaker/ProcessingJobs/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-processing-logs"
  })
}

resource "aws_cloudwatch_log_group" "endpoints" {
  name              = "/aws/sagemaker/Endpoints/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-endpoint-logs"
  })
}

# =============================================================================
# CloudWatch Dashboard (Optional)
# =============================================================================

resource "aws_cloudwatch_dashboard" "sagemaker" {
  count = var.enable_cloudwatch_metrics ? 1 : 0

  dashboard_name = "${var.stack_name}-sagemaker"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SageMaker", "Invocations", "EndpointName", var.stack_name, "VariantName", "AllTraffic"],
            [".", "ModelLatency", ".", ".", ".", "."],
            [".", "Invocation5XXErrors", ".", ".", ".", "."],
            [".", "Invocation4XXErrors", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "Endpoint Metrics"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SageMaker", "CPUUtilization", "EndpointName", var.stack_name, "VariantName", "AllTraffic"],
            [".", "MemoryUtilization", ".", ".", ".", "."],
            [".", "GPUUtilization", ".", ".", ".", "."],
            [".", "GPUMemoryUtilization", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "Resource Utilization"
          period  = 60
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/sagemaker/TrainingJobs/${var.stack_name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = local.region
          title  = "Training Job Logs"
        }
      }
    ]
  })
}

# =============================================================================
# CloudWatch Alarms (Optional)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "endpoint_5xx_errors" {
  count = var.enable_cloudwatch_metrics ? 1 : 0

  alarm_name          = "${var.stack_name}-endpoint-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Invocation5XXErrors"
  namespace           = "AWS/SageMaker"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alarm when endpoint returns more than 10 5XX errors in 2 minutes"

  dimensions = {
    EndpointName = var.stack_name
    VariantName  = "AllTraffic"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "endpoint_latency" {
  count = var.enable_cloudwatch_metrics ? 1 : 0

  alarm_name          = "${var.stack_name}-endpoint-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ModelLatency"
  namespace           = "AWS/SageMaker"
  period              = 60
  statistic           = "Average"
  threshold           = 5000000 # 5 seconds in microseconds
  alarm_description   = "Alarm when average model latency exceeds 5 seconds"

  dimensions = {
    EndpointName = var.stack_name
    VariantName  = "AllTraffic"
  }

  tags = local.common_tags
}
