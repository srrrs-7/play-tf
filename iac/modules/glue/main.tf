# Glue Catalog Database
resource "aws_glue_catalog_database" "this" {
  count = var.create_database ? 1 : 0

  name         = var.database_name
  catalog_id   = var.catalog_id
  description  = var.database_description
  location_uri = var.database_location_uri

  dynamic "create_table_default_permission" {
    for_each = var.database_create_table_default_permission != null ? [var.database_create_table_default_permission] : []
    content {
      permissions = create_table_default_permission.value.permissions

      dynamic "principal" {
        for_each = create_table_default_permission.value.principal != null ? [create_table_default_permission.value.principal] : []
        content {
          data_lake_principal_identifier = principal.value.data_lake_principal_identifier
        }
      }
    }
  }

  dynamic "target_database" {
    for_each = var.target_database != null ? [var.target_database] : []
    content {
      catalog_id    = target_database.value.catalog_id
      database_name = target_database.value.database_name
      region        = lookup(target_database.value, "region", null)
    }
  }

  tags = var.tags
}

# Glue Connection
resource "aws_glue_connection" "this" {
  for_each = { for conn in var.connections : conn.name => conn }

  name            = each.value.name
  catalog_id      = var.catalog_id
  connection_type = lookup(each.value, "connection_type", "JDBC")
  description     = lookup(each.value, "description", null)

  connection_properties = each.value.connection_properties

  dynamic "physical_connection_requirements" {
    for_each = lookup(each.value, "physical_connection_requirements", null) != null ? [each.value.physical_connection_requirements] : []
    content {
      availability_zone      = lookup(physical_connection_requirements.value, "availability_zone", null)
      security_group_id_list = lookup(physical_connection_requirements.value, "security_group_id_list", null)
      subnet_id              = lookup(physical_connection_requirements.value, "subnet_id", null)
    }
  }

  match_criteria = lookup(each.value, "match_criteria", null)

  tags = var.tags
}

# Glue Crawler
resource "aws_glue_crawler" "this" {
  for_each = { for crawler in var.crawlers : crawler.name => crawler }

  name          = each.value.name
  database_name = var.create_database ? aws_glue_catalog_database.this[0].name : each.value.database_name
  role          = each.value.role_arn
  description   = lookup(each.value, "description", null)
  classifiers   = lookup(each.value, "classifiers", null)
  configuration = lookup(each.value, "configuration", null)
  schedule      = lookup(each.value, "schedule", null)
  table_prefix  = lookup(each.value, "table_prefix", null)

  # S3ターゲット
  dynamic "s3_target" {
    for_each = lookup(each.value, "s3_targets", [])
    content {
      path                = s3_target.value.path
      connection_name     = lookup(s3_target.value, "connection_name", null)
      exclusions          = lookup(s3_target.value, "exclusions", null)
      sample_size         = lookup(s3_target.value, "sample_size", null)
      event_queue_arn     = lookup(s3_target.value, "event_queue_arn", null)
      dlq_event_queue_arn = lookup(s3_target.value, "dlq_event_queue_arn", null)
    }
  }

  # JDBCターゲット
  dynamic "jdbc_target" {
    for_each = lookup(each.value, "jdbc_targets", [])
    content {
      connection_name            = jdbc_target.value.connection_name
      path                       = jdbc_target.value.path
      exclusions                 = lookup(jdbc_target.value, "exclusions", null)
      enable_additional_metadata = lookup(jdbc_target.value, "enable_additional_metadata", null)
    }
  }

  # DynamoDBターゲット
  dynamic "dynamodb_target" {
    for_each = lookup(each.value, "dynamodb_targets", [])
    content {
      path      = dynamodb_target.value.path
      scan_all  = lookup(dynamodb_target.value, "scan_all", null)
      scan_rate = lookup(dynamodb_target.value, "scan_rate", null)
    }
  }

  # カタログターゲット
  dynamic "catalog_target" {
    for_each = lookup(each.value, "catalog_targets", [])
    content {
      database_name       = catalog_target.value.database_name
      tables              = catalog_target.value.tables
      connection_name     = lookup(catalog_target.value, "connection_name", null)
      event_queue_arn     = lookup(catalog_target.value, "event_queue_arn", null)
      dlq_event_queue_arn = lookup(catalog_target.value, "dlq_event_queue_arn", null)
    }
  }

  # Delta Lakeターゲット
  dynamic "delta_target" {
    for_each = lookup(each.value, "delta_targets", [])
    content {
      delta_tables          = delta_target.value.delta_tables
      connection_name       = lookup(delta_target.value, "connection_name", null)
      write_manifest        = lookup(delta_target.value, "write_manifest", false)
      create_native_delta_table = lookup(delta_target.value, "create_native_delta_table", false)
    }
  }

  # スキーマ変更ポリシー
  dynamic "schema_change_policy" {
    for_each = lookup(each.value, "schema_change_policy", null) != null ? [each.value.schema_change_policy] : []
    content {
      delete_behavior = lookup(schema_change_policy.value, "delete_behavior", null)
      update_behavior = lookup(schema_change_policy.value, "update_behavior", null)
    }
  }

  # 再クロール設定
  dynamic "recrawl_policy" {
    for_each = lookup(each.value, "recrawl_policy", null) != null ? [each.value.recrawl_policy] : []
    content {
      recrawl_behavior = recrawl_policy.value.recrawl_behavior
    }
  }

  # Lineage設定
  dynamic "lineage_configuration" {
    for_each = lookup(each.value, "lineage_configuration", null) != null ? [each.value.lineage_configuration] : []
    content {
      crawler_lineage_settings = lineage_configuration.value.crawler_lineage_settings
    }
  }

  # Lake Formation設定
  dynamic "lake_formation_configuration" {
    for_each = lookup(each.value, "lake_formation_configuration", null) != null ? [each.value.lake_formation_configuration] : []
    content {
      account_id                     = lookup(lake_formation_configuration.value, "account_id", null)
      use_lake_formation_credentials = lookup(lake_formation_configuration.value, "use_lake_formation_credentials", null)
    }
  }

  security_configuration = lookup(each.value, "security_configuration", null)

  tags = var.tags

  depends_on = [aws_glue_catalog_database.this]
}

# Glue Job
resource "aws_glue_job" "this" {
  for_each = { for job in var.jobs : job.name => job }

  name              = each.value.name
  role_arn          = each.value.role_arn
  description       = lookup(each.value, "description", null)
  glue_version      = lookup(each.value, "glue_version", "4.0")
  max_capacity      = lookup(each.value, "max_capacity", null)
  max_retries       = lookup(each.value, "max_retries", 0)
  timeout           = lookup(each.value, "timeout", 2880)
  worker_type       = lookup(each.value, "worker_type", null)
  number_of_workers = lookup(each.value, "number_of_workers", null)

  # コマンド設定
  command {
    name            = lookup(each.value.command, "name", "glueetl")
    script_location = each.value.command.script_location
    python_version  = lookup(each.value.command, "python_version", "3")
    runtime         = lookup(each.value.command, "runtime", null)
  }

  # デフォルト引数
  default_arguments = lookup(each.value, "default_arguments", null)

  # 非オーバーライド引数
  non_overridable_arguments = lookup(each.value, "non_overridable_arguments", null)

  # 接続
  connections = lookup(each.value, "connections", null)

  # 実行プロパティ
  dynamic "execution_property" {
    for_each = lookup(each.value, "max_concurrent_runs", null) != null ? [1] : []
    content {
      max_concurrent_runs = each.value.max_concurrent_runs
    }
  }

  # 通知プロパティ
  dynamic "notification_property" {
    for_each = lookup(each.value, "notify_delay_after", null) != null ? [1] : []
    content {
      notify_delay_after = each.value.notify_delay_after
    }
  }

  # セキュリティ設定
  security_configuration = lookup(each.value, "security_configuration", null)

  # 実行クラス
  execution_class = lookup(each.value, "execution_class", null)

  tags = var.tags
}

# Glue Trigger
resource "aws_glue_trigger" "this" {
  for_each = { for trigger in var.triggers : trigger.name => trigger }

  name        = each.value.name
  type        = each.value.type
  description = lookup(each.value, "description", null)
  enabled     = lookup(each.value, "enabled", true)
  schedule    = lookup(each.value, "schedule", null)
  workflow_name = lookup(each.value, "workflow_name", null)
  start_on_creation = lookup(each.value, "start_on_creation", false)

  # アクション
  dynamic "actions" {
    for_each = each.value.actions
    content {
      job_name               = lookup(actions.value, "job_name", null)
      crawler_name           = lookup(actions.value, "crawler_name", null)
      arguments              = lookup(actions.value, "arguments", null)
      timeout                = lookup(actions.value, "timeout", null)
      security_configuration = lookup(actions.value, "security_configuration", null)

      dynamic "notification_property" {
        for_each = lookup(actions.value, "notify_delay_after", null) != null ? [1] : []
        content {
          notify_delay_after = actions.value.notify_delay_after
        }
      }
    }
  }

  # 条件（CONDITIONALタイプの場合）
  dynamic "predicate" {
    for_each = each.value.type == "CONDITIONAL" && lookup(each.value, "predicate", null) != null ? [each.value.predicate] : []
    content {
      logical = lookup(predicate.value, "logical", "AND")

      dynamic "conditions" {
        for_each = predicate.value.conditions
        content {
          job_name         = lookup(conditions.value, "job_name", null)
          crawler_name     = lookup(conditions.value, "crawler_name", null)
          state            = lookup(conditions.value, "state", null)
          crawl_state      = lookup(conditions.value, "crawl_state", null)
          logical_operator = lookup(conditions.value, "logical_operator", "EQUALS")
        }
      }
    }
  }

  # イベントバッチング条件（EVENT タイプの場合）
  dynamic "event_batching_condition" {
    for_each = each.value.type == "EVENT" && lookup(each.value, "event_batching_condition", null) != null ? [each.value.event_batching_condition] : []
    content {
      batch_size   = event_batching_condition.value.batch_size
      batch_window = lookup(event_batching_condition.value, "batch_window", null)
    }
  }

  tags = var.tags

  depends_on = [aws_glue_job.this, aws_glue_crawler.this]
}

# Glue Workflow
resource "aws_glue_workflow" "this" {
  for_each = { for workflow in var.workflows : workflow.name => workflow }

  name                = each.value.name
  description         = lookup(each.value, "description", null)
  default_run_properties = lookup(each.value, "default_run_properties", null)
  max_concurrent_runs = lookup(each.value, "max_concurrent_runs", null)

  tags = var.tags
}

# Glue Security Configuration
resource "aws_glue_security_configuration" "this" {
  count = var.create_security_configuration ? 1 : 0

  name = var.security_configuration_name

  encryption_configuration {
    dynamic "cloudwatch_encryption" {
      for_each = var.cloudwatch_encryption != null ? [var.cloudwatch_encryption] : []
      content {
        cloudwatch_encryption_mode = cloudwatch_encryption.value.mode
        kms_key_arn                = lookup(cloudwatch_encryption.value, "kms_key_arn", null)
      }
    }

    dynamic "job_bookmarks_encryption" {
      for_each = var.job_bookmarks_encryption != null ? [var.job_bookmarks_encryption] : []
      content {
        job_bookmarks_encryption_mode = job_bookmarks_encryption.value.mode
        kms_key_arn                   = lookup(job_bookmarks_encryption.value, "kms_key_arn", null)
      }
    }

    dynamic "s3_encryption" {
      for_each = var.s3_encryption != null ? [var.s3_encryption] : []
      content {
        s3_encryption_mode = s3_encryption.value.mode
        kms_key_arn        = lookup(s3_encryption.value, "kms_key_arn", null)
      }
    }
  }
}
