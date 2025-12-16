# =============================================================================
# EC2 Instance（プライベートサブネット）
# =============================================================================
# プライベートサブネットに配置されるEC2インスタンス:
# - パブリックIPなし
# - Session Manager経由でのみアクセス可能
# - NAT Instance経由でインターネットアクセス
# - VPC Endpoint経由でS3アクセス

resource "aws_instance" "ec2" {
  count                = var.create_ec2_instance ? 1 : 0
  ami                  = local.ec2_ami_id
  instance_type        = var.ec2_instance_type
  subnet_id            = aws_subnet.private.id
  iam_instance_profile = aws_iam_instance_profile.ec2.name

  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = false # プライベートサブネットのためパブリックIPなし

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ec2_root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  # IMDSv2を強制（セキュリティ強化）
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2必須
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ec2"
  })

  lifecycle {
    ignore_changes = [ami]
  }

  # SSM Endpointsが作成されるのを待つ（Session Manager接続に必要）
  depends_on = [
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
  ]
}
