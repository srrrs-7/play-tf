# =============================================================================
# DynamoDB Table
# =============================================================================

resource "aws_dynamodb_table" "main" {
  name         = coalesce(var.dynamodb_table_name, var.stack_name)
  billing_mode = var.dynamodb_billing_mode
  hash_key     = var.dynamodb_hash_key

  attribute {
    name = var.dynamodb_hash_key
    type = var.dynamodb_hash_key_type
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = coalesce(var.dynamodb_table_name, var.stack_name)
  })
}
