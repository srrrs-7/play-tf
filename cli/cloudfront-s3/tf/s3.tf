# =============================================================================
# S3 Bucket
# =============================================================================
# 静的ファイルをホストするS3バケット
# - パブリックアクセスブロック（CloudFront OAC経由のみアクセス可能）
# - 暗号化有効
# - オプションでバージョニング

resource "aws_s3_bucket" "static" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, var.tags, {
    Name = local.s3_bucket_name
  })
}

# =============================================================================
# S3 Bucket Configuration
# =============================================================================

# バージョニング設定
resource "aws_s3_bucket_versioning" "static" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.static.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 暗号化設定（AES256）
resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# パブリックアクセスブロック（すべてブロック）
resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Bucket Policy for CloudFront OAC
# =============================================================================
# CloudFront OAC (Origin Access Control) からのアクセスのみ許可

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })

  # CloudFrontディストリビューションが作成されてからポリシーを適用
  depends_on = [aws_s3_bucket_public_access_block.static]
}

# =============================================================================
# S3 CORS Configuration (Optional for SPA)
# =============================================================================
# SPAでAPI呼び出しが必要な場合のCORS設定

resource "aws_s3_bucket_cors_configuration" "static" {
  count  = var.enable_spa_mode ? 1 : 0
  bucket = aws_s3_bucket.static.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
