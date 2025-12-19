# =============================================================================
# EC2/ECS Security Group
# =============================================================================
# EC2インスタンス用のセキュリティグループ
# VPC内部からの通信を許可、外部へのアウトバウンドを許可

resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for ECS EC2 instances - allows outbound and VPC internal traffic"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ec2-sg"
  })
}

# VPC内部からの全トラフィックを許可（コンテナ間通信用）
resource "aws_vpc_security_group_ingress_rule" "ec2_vpc" {
  security_group_id = aws_security_group.ec2.id
  description       = "All traffic from VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "all-from-vpc"
  }
}

# 外部への全アウトバウンドを許可（ECR pull, Session Manager等）
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}
