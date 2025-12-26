# =============================================================================
# S3 Buckets for SageMaker
# =============================================================================

# Input data bucket
resource "aws_s3_bucket" "input" {
  count = var.create_s3_buckets ? 1 : 0

  bucket        = local.input_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name    = local.input_bucket_name
    Purpose = "SageMaker input data"
  })
}

# Output/results bucket
resource "aws_s3_bucket" "output" {
  count = var.create_s3_buckets ? 1 : 0

  bucket        = local.output_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name    = local.output_bucket_name
    Purpose = "SageMaker output data"
  })
}

# Model artifacts bucket
resource "aws_s3_bucket" "model" {
  count = var.create_s3_buckets ? 1 : 0

  bucket        = local.model_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name    = local.model_bucket_name
    Purpose = "SageMaker model artifacts"
  })
}

# =============================================================================
# S3 Bucket Versioning
# =============================================================================

resource "aws_s3_bucket_versioning" "input" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.input[0].id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.output[0].id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "model" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.model[0].id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# =============================================================================
# S3 Bucket Encryption
# =============================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.input[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.output[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.model[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# S3 Public Access Block
# =============================================================================

resource "aws_s3_bucket_public_access_block" "input" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.input[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.output[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "model" {
  count = var.create_s3_buckets ? 1 : 0

  bucket = aws_s3_bucket.model[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Lifecycle Rules (optional)
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "output" {
  count = var.create_s3_buckets && var.s3_lifecycle_expiration_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.output[0].id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_lifecycle_expiration_days
    }
  }
}

# =============================================================================
# S3 Initial Folder Structure
# =============================================================================

# Create folder structure in input bucket
resource "aws_s3_object" "training_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.input[0].id
  key     = "training/.gitkeep"
  content = ""
}

resource "aws_s3_object" "validation_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.input[0].id
  key     = "validation/.gitkeep"
  content = ""
}

resource "aws_s3_object" "test_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.input[0].id
  key     = "test/.gitkeep"
  content = ""
}

# Create folder structure in output bucket
resource "aws_s3_object" "output_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.output[0].id
  key     = "output/.gitkeep"
  content = ""
}

resource "aws_s3_object" "processing_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.output[0].id
  key     = "processing/.gitkeep"
  content = ""
}

# Create folder structure in model bucket
resource "aws_s3_object" "models_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.model[0].id
  key     = "models/.gitkeep"
  content = ""
}

resource "aws_s3_object" "artifacts_folder" {
  count = var.create_s3_buckets ? 1 : 0

  bucket  = aws_s3_bucket.model[0].id
  key     = "artifacts/.gitkeep"
  content = ""
}
