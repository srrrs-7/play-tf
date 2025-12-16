# =============================================================================
# S3 Bucket
# =============================================================================
# プライベートサブネットのEC2からVPC Endpoint経由でアクセスするS3バケット
# - パブリックアクセスブロック
# - バージョニング有効
# - 暗号化有効

# バケット名の生成（指定がない場合は自動生成）
locals {
  s3_bucket_name = var.s3_bucket_name != null ? var.s3_bucket_name : "${local.name_prefix}-bucket-${random_id.bucket_suffix[0].hex}"
}

# バケット名サフィックス用のランダムID
resource "random_id" "bucket_suffix" {
  count       = var.create_s3_bucket && var.s3_bucket_name == null ? 1 : 0
  byte_length = 4
}

# S3 Bucket
resource "aws_s3_bucket" "main" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, var.tags, {
    Name = local.s3_bucket_name
  })
}

# バージョニング設定
resource "aws_s3_bucket_versioning" "main" {
  count  = var.create_s3_bucket && var.s3_enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.main[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# 暗号化設定（AES256）
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.main[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# パブリックアクセスブロック（全て有効）
resource "aws_s3_bucket_public_access_block" "main" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.main[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
