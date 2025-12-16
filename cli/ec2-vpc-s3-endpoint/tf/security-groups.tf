# =============================================================================
# NAT Instance Security Group
# =============================================================================
# プライベートサブネットからのトラフィックをインターネットへ転送するための設定
# - HTTP (80): パッケージ更新（yum/apt）
# - HTTPS (443): Git, npm, HTTPS通信
# - ICMP: ping疎通確認

resource "aws_security_group" "nat" {
  count       = var.create_nat_instance ? 1 : 0
  name        = "${local.name_prefix}-nat-sg"
  description = "Security group for NAT Instance"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-nat-sg"
  })
}

# HTTP (80) from VPC - パッケージ更新用
resource "aws_vpc_security_group_ingress_rule" "nat_http" {
  count             = var.create_nat_instance ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  description       = "HTTP from VPC for package updates"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "http-from-vpc"
  }
}

# HTTPS (443) from VPC - Git, npm, HTTPS通信用
resource "aws_vpc_security_group_ingress_rule" "nat_https" {
  count             = var.create_nat_instance ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  description       = "HTTPS from VPC for Git, npm, etc."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "https-from-vpc"
  }
}

# ICMP from VPC - ping疎通確認用
resource "aws_vpc_security_group_ingress_rule" "nat_icmp" {
  count             = var.create_nat_instance ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  description       = "ICMP from VPC for connectivity testing"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "icmp-from-vpc"
  }
}

# Egress: All traffic to internet
resource "aws_vpc_security_group_egress_rule" "nat_all" {
  count             = var.create_nat_instance ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  description       = "All traffic to internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-to-internet"
  }
}

# =============================================================================
# EC2 Security Group
# =============================================================================
# VPC Endpoint経由でAWSサービスにアクセスするための設定
# - HTTPS (443): VPC Endpoint通信

resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for EC2 with VPC Endpoint access"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ec2-sg"
  })
}

# HTTPS (443) from VPC - VPC Endpoint用
resource "aws_vpc_security_group_ingress_rule" "ec2_https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS from VPC for VPC Endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "https-from-vpc"
  }
}

# Egress: All traffic (NAT Instance経由でインターネット、VPC Endpoint経由でAWSサービス)
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All traffic to NAT Instance and VPC Endpoints"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}

# =============================================================================
# VPC Endpoint Security Group（SSM Interface Endpoints用）
# =============================================================================

resource "aws_security_group" "vpc_endpoints" {
  count       = var.create_ssm_endpoints ? 1 : 0
  name        = "${local.name_prefix}-vpce-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })
}

# HTTPS (443) from VPC - VPC Endpoint用
resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  count             = var.create_ssm_endpoints ? 1 : 0
  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from VPC for VPC Endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "https-from-vpc"
  }
}

# Egress: All traffic
resource "aws_vpc_security_group_egress_rule" "vpce_all" {
  count             = var.create_ssm_endpoints ? 1 : 0
  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}
