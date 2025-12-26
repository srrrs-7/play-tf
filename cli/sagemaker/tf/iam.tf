# =============================================================================
# IAM Role for SageMaker
# =============================================================================

# Trust policy for SageMaker service
data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# SageMaker execution role
resource "aws_iam_role" "sagemaker_execution" {
  count = var.create_iam_role ? 1 : 0

  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json

  tags = merge(local.common_tags, {
    Name = var.iam_role_name
  })
}

# Managed policies for SageMaker execution role
locals {
  sagemaker_managed_policies = [
    "arn:${local.partition}:iam::aws:policy/AmazonSageMakerFullAccess",
    "arn:${local.partition}:iam::aws:policy/AmazonS3FullAccess",
    "arn:${local.partition}:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]
}

# Attach managed policies to SageMaker execution role
resource "aws_iam_role_policy_attachment" "sagemaker_policies" {
  for_each = var.create_iam_role ? toset(local.sagemaker_managed_policies) : toset([])

  role       = aws_iam_role.sagemaker_execution[0].name
  policy_arn = each.value
}

# Attach additional policies if specified
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = var.create_iam_role ? toset(var.additional_iam_policies) : toset([])

  role       = aws_iam_role.sagemaker_execution[0].name
  policy_arn = each.value
}

# Custom policy for S3 bucket access (more restrictive alternative)
data "aws_iam_policy_document" "sagemaker_s3_access" {
  count = var.create_iam_role && var.create_s3_buckets ? 1 : 0

  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.input[0].arn,
      "${aws_s3_bucket.input[0].arn}/*",
      aws_s3_bucket.output[0].arn,
      "${aws_s3_bucket.output[0].arn}/*",
      aws_s3_bucket.model[0].arn,
      "${aws_s3_bucket.model[0].arn}/*"
    ]
  }

  statement {
    sid    = "S3ListAllBuckets"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets"
    ]
    resources = ["*"]
  }
}

# Custom policy for KMS access (if using encrypted buckets)
data "aws_iam_policy_document" "sagemaker_kms_access" {
  count = var.create_iam_role ? 1 : 0

  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
  }
}

# Custom policy for VPC access (if using VPC mode)
data "aws_iam_policy_document" "sagemaker_vpc_access" {
  count = var.create_iam_role && var.vpc_id != null ? 1 : 0

  statement {
    sid    = "VPCAccess"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
      "ec2:DeleteNetworkInterfacePermission",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sagemaker_vpc" {
  count = var.create_iam_role && var.vpc_id != null ? 1 : 0

  name   = "${var.iam_role_name}-vpc-policy"
  role   = aws_iam_role.sagemaker_execution[0].id
  policy = data.aws_iam_policy_document.sagemaker_vpc_access[0].json
}

# Local value for role ARN (either created or provided)
locals {
  sagemaker_role_arn = var.create_iam_role ? aws_iam_role.sagemaker_execution[0].arn : var.existing_role_arn
}
