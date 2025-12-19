# =============================================================================
# S3 Bucket
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "main" {
  bucket        = coalesce(var.s3_bucket_name, "${local.name_prefix}-${random_id.bucket_suffix.hex}")
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = coalesce(var.s3_bucket_name, "${local.name_prefix}-${random_id.bucket_suffix.hex}")
  })
}

# Versioning
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule (optional)
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  count  = var.s3_lifecycle_expire_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "expire-old-data"
    status = "Enabled"

    filter {
      prefix = var.s3_prefix
    }

    expiration {
      days = var.s3_lifecycle_expire_days
    }
  }
}
