resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine            = var.engine
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = var.port

  vpc_security_group_ids = var.vpc_security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name
  parameter_group_name   = var.parameter_group_name
  option_group_name      = var.option_group_name

  availability_zone   = var.availability_zone
  multi_az            = var.multi_az
  publicly_accessible = var.publicly_accessible

  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  apply_immediately           = var.apply_immediately
  maintenance_window          = var.maintenance_window

  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  copy_tags_to_snapshot     = var.copy_tags_to_snapshot
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? var.monitoring_role_arn : null

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  deletion_protection = var.deletion_protection

  tags = var.tags
}

resource "aws_db_subnet_group" "this" {
  count = var.create_db_subnet_group ? 1 : 0

  name        = var.db_subnet_group_name
  description = "Database subnet group for ${var.identifier}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_db_parameter_group" "this" {
  count = var.create_db_parameter_group ? 1 : 0

  name        = var.parameter_group_name
  description = "Database parameter group for ${var.identifier}"
  family      = var.family

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = var.tags
}

resource "aws_db_option_group" "this" {
  count = var.create_db_option_group ? 1 : 0

  name                     = var.option_group_name
  option_group_description = "Database option group for ${var.identifier}"
  engine_name              = var.engine
  major_engine_version     = var.major_engine_version

  dynamic "option" {
    for_each = var.options
    content {
      option_name = option.value.option_name

      dynamic "option_settings" {
        for_each = lookup(option.value, "option_settings", [])
        content {
          name  = option_settings.value.name
          value = option_settings.value.value
        }
      }
    }
  }

  tags = var.tags
}
