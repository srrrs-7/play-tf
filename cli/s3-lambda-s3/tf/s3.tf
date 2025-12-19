# =============================================================================
# Random Suffix for Bucket Names
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# Source S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "source" {
  bucket        = coalesce(var.source_bucket_name, "${local.name_prefix}-source-${random_id.bucket_suffix.hex}")
  force_destroy = var.source_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-source"
    Role = "source"
  })
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# Destination S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "dest" {
  bucket        = coalesce(var.dest_bucket_name, "${local.name_prefix}-dest-${random_id.bucket_suffix.hex}")
  force_destroy = var.dest_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dest"
    Role = "destination"
  })
}

resource "aws_s3_bucket_versioning" "dest" {
  bucket = aws_s3_bucket.dest.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dest" {
  bucket = aws_s3_bucket.dest.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dest" {
  bucket = aws_s3_bucket.dest.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Event Notification
# =============================================================================

resource "aws_s3_bucket_notification" "source" {
  bucket = aws_s3_bucket.source.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main.arn
    events              = var.trigger_events
    filter_prefix       = var.trigger_prefix
    filter_suffix       = var.trigger_suffix
  }

  depends_on = [aws_lambda_permission.s3]
}
