# =============================================================================
# IAM Role for EC2
# =============================================================================
# EC2インスタンスに付与するIAMロール:
# - AmazonSSMManagedInstanceCore: Session Manager接続に必要
# - AmazonS3ReadOnlyAccess or AmazonS3FullAccess: S3アクセス

# Trust Policy（EC2がこのロールを引き受けることを許可）
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM Role
resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM Role for EC2 with SSM and S3 access"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ec2-role"
  })
}

# SSM Managed Policy（Session Manager接続に必要）
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 Policy（読み取り専用またはフルアクセス）
resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.ec2.name
  policy_arn = var.s3_full_access ? "arn:aws:iam::aws:policy/AmazonS3FullAccess" : "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Instance Profile（EC2にロールを付与するために必要）
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ec2-profile"
  })
}
