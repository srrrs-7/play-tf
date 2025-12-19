# =============================================================================
# S3 Buckets
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Input bucket
resource "aws_s3_bucket" "input" {
  count = var.create_s3_buckets ? 1 : 0

  bucket        = "${local.name_prefix}-input-${random_id.bucket_suffix.hex}"
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-input"
    Role = "input"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  count  = var.create_s3_buckets ? 1 : 0
  bucket = aws_s3_bucket.input[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "input" {
  count  = var.create_s3_buckets ? 1 : 0
  bucket = aws_s3_bucket.input[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output bucket
resource "aws_s3_bucket" "output" {
  count = var.create_s3_buckets ? 1 : 0

  bucket        = "${local.name_prefix}-output-${random_id.bucket_suffix.hex}"
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-output"
    Role = "output"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  count  = var.create_s3_buckets ? 1 : 0
  bucket = aws_s3_bucket.output[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "output" {
  count  = var.create_s3_buckets ? 1 : 0
  bucket = aws_s3_bucket.output[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
