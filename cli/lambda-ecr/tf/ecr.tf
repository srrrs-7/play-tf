# =============================================================================
# ECR Repository
# =============================================================================

resource "aws_ecr_repository" "main" {
  name                 = var.stack_name
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecr"
  })
}

# =============================================================================
# ECR Lifecycle Policy
# =============================================================================

resource "aws_ecr_lifecycle_policy" "main" {
  count = var.ecr_lifecycle_policy_count > 0 ? 1 : 0

  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_lifecycle_policy_count} images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_lifecycle_policy_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# ECR Repository Policy (Allow Lambda to pull images)
# =============================================================================

resource "aws_ecr_repository_policy" "lambda_access" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaECRImageRetrievalPolicy"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Condition = {
          StringLike = {
            "aws:sourceArn" = "arn:aws:lambda:${local.region}:${local.account_id}:function:${var.stack_name}*"
          }
        }
      }
    ]
  })
}
