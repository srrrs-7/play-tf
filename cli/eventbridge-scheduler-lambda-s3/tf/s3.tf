# =============================================================================
# S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "data" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-bucket"
  })
}

# =============================================================================
# S3 Bucket Configuration
# =============================================================================

# パブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 暗号化設定
resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# バージョニング設定
resource "aws_s3_bucket_versioning" "data" {
  count  = var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ライフサイクルルール
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  count  = var.s3_lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_days
    }

    filter {
      prefix = "metrics/"
    }
  }
}
