# =============================================================================
# DynamoDB Table
# =============================================================================

resource "aws_dynamodb_table" "main" {
  name         = coalesce(var.dynamodb_table_name, var.stack_name)
  billing_mode = var.dynamodb_billing_mode

  hash_key  = var.dynamodb_hash_key
  range_key = var.dynamodb_range_key

  attribute {
    name = var.dynamodb_hash_key
    type = var.dynamodb_hash_key_type
  }

  dynamic "attribute" {
    for_each = var.dynamodb_range_key != null ? [1] : []
    content {
      name = var.dynamodb_range_key
      type = var.dynamodb_range_key_type
    }
  }

  dynamic "ttl" {
    for_each = var.dynamodb_enable_ttl ? [1] : []
    content {
      attribute_name = var.dynamodb_ttl_attribute
      enabled        = true
    }
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = coalesce(var.dynamodb_table_name, var.stack_name)
  })
}
