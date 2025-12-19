# =============================================================================
# DynamoDB Table
# =============================================================================

resource "aws_dynamodb_table" "main" {
  name         = coalesce(var.dynamodb_table_name, var.stack_name)
  billing_mode = var.dynamodb_billing_mode

  # Provisioned capacity (only used when billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  # Hash key (partition key)
  hash_key = var.dynamodb_hash_key

  # Range key (sort key) - optional
  range_key = var.dynamodb_range_key

  # Hash key attribute
  attribute {
    name = var.dynamodb_hash_key
    type = var.dynamodb_hash_key_type
  }

  # Range key attribute (if specified)
  dynamic "attribute" {
    for_each = var.dynamodb_range_key != null ? [1] : []
    content {
      name = var.dynamodb_range_key
      type = var.dynamodb_range_key_type
    }
  }

  # GSI key attributes
  dynamic "attribute" {
    for_each = { for gsi in var.dynamodb_global_secondary_indexes : gsi.hash_key => gsi if gsi.hash_key != var.dynamodb_hash_key && (var.dynamodb_range_key == null || gsi.hash_key != var.dynamodb_range_key) }
    content {
      name = attribute.value.hash_key
      type = attribute.value.hash_key_type
    }
  }

  dynamic "attribute" {
    for_each = { for gsi in var.dynamodb_global_secondary_indexes : gsi.range_key => gsi if gsi.range_key != null && gsi.range_key != var.dynamodb_hash_key && (var.dynamodb_range_key == null || gsi.range_key != var.dynamodb_range_key) }
    content {
      name = attribute.value.range_key
      type = attribute.value.range_key_type
    }
  }

  # Global Secondary Indexes
  dynamic "global_secondary_index" {
    for_each = var.dynamodb_global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type

      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null

      # For provisioned billing mode
      read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
      write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    }
  }

  # TTL configuration
  dynamic "ttl" {
    for_each = var.dynamodb_enable_ttl ? [1] : []
    content {
      attribute_name = var.dynamodb_ttl_attribute
      enabled        = true
    }
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.dynamodb_enable_point_in_time_recovery
  }

  # Server-side encryption (always enabled with AWS managed key)
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = coalesce(var.dynamodb_table_name, var.stack_name)
  })
}
