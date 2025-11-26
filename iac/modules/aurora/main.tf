# Aurora Cluster
resource "aws_rds_cluster" "main" {
  cluster_identifier = var.cluster_identifier
  engine             = var.engine
  engine_mode        = var.engine_mode
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  db_subnet_group_name   = var.create_db_subnet_group ? aws_db_subnet_group.main[0].name : var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids

  port                      = var.port
  network_type              = var.network_type
  db_cluster_instance_class = var.engine_mode == "provisioned" && var.db_cluster_instance_class != null ? var.db_cluster_instance_class : null
  storage_type              = var.storage_type
  allocated_storage         = var.allocated_storage
  iops                      = var.iops

  # Serverless v2 scaling configuration
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.engine_mode == "provisioned" && var.serverlessv2_scaling_configuration != null ? [var.serverlessv2_scaling_configuration] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  # Backup and maintenance
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${var.cluster_identifier}-final-snapshot"
  copy_tags_to_snapshot        = var.copy_tags_to_snapshot

  # Encryption
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # IAM authentication
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # Deletion protection
  deletion_protection = var.deletion_protection

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # DB parameter group
  db_cluster_parameter_group_name = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.main[0].name : var.db_cluster_parameter_group_name

  # Performance Insights
  dynamic "scaling_configuration" {
    for_each = var.engine_mode == "serverless" && var.scaling_configuration != null ? [var.scaling_configuration] : []
    content {
      auto_pause               = lookup(scaling_configuration.value, "auto_pause", true)
      min_capacity             = lookup(scaling_configuration.value, "min_capacity", 1)
      max_capacity             = lookup(scaling_configuration.value, "max_capacity", 2)
      seconds_until_auto_pause = lookup(scaling_configuration.value, "seconds_until_auto_pause", 300)
      timeout_action           = lookup(scaling_configuration.value, "timeout_action", "RollbackCapacityChange")
    }
  }

  apply_immediately = var.apply_immediately

  tags = merge(
    var.tags,
    {
      Name = var.cluster_identifier
    }
  )

  lifecycle {
    ignore_changes = [
      master_password,
      availability_zones
    ]
  }
}

# Aurora Cluster Instances
resource "aws_rds_cluster_instance" "main" {
  count = var.engine_mode != "serverless" ? var.instance_count : 0

  identifier         = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = var.engine
  engine_version     = var.engine_version

  db_subnet_group_name    = var.create_db_subnet_group ? aws_db_subnet_group.main[0].name : var.db_subnet_group_name
  db_parameter_group_name = var.create_db_parameter_group ? aws_db_parameter_group.main[0].name : var.db_parameter_group_name
  publicly_accessible     = var.publicly_accessible
  ca_cert_identifier      = var.ca_cert_identifier

  # Performance Insights
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_kms_key_id
  performance_insights_retention_period = var.performance_insights_retention_period

  # Enhanced Monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_role_arn

  # Maintenance
  preferred_maintenance_window = var.preferred_maintenance_window
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade

  apply_immediately = var.apply_immediately

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-${count.index + 1}"
    }
  )
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  count = var.create_db_subnet_group ? 1 : 0

  name        = "${var.cluster_identifier}-subnet-group"
  description = "Subnet group for ${var.cluster_identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-subnet-group"
    }
  )
}

# Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "main" {
  count = var.create_cluster_parameter_group ? 1 : 0

  name        = "${var.cluster_identifier}-cluster-params"
  family      = var.parameter_group_family
  description = "Cluster parameter group for ${var.cluster_identifier}"

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-cluster-params"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  count = var.create_db_parameter_group ? 1 : 0

  name        = "${var.cluster_identifier}-db-params"
  family      = var.parameter_group_family
  description = "DB parameter group for ${var.cluster_identifier}"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-db-params"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group (optional)
resource "aws_security_group" "aurora" {
  count = var.create_security_group ? 1 : 0

  name        = "${var.cluster_identifier}-sg"
  description = "Security group for ${var.cluster_identifier} Aurora cluster"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    cidr_blocks     = var.allowed_cidr_blocks
    security_groups = var.allowed_security_groups
    description     = "Allow database connections"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-sg"
    }
  )
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "monitoring" {
  count = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0

  name = "${var.cluster_identifier}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms (optional)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.cluster_identifier}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors Aurora CPU utilization"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_low" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.cluster_identifier}-freeable-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "This metric monitors Aurora freeable memory"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = var.tags
}
