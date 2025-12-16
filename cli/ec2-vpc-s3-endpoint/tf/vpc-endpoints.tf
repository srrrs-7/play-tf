# =============================================================================
# S3 Gateway VPC Endpoint（無料）
# =============================================================================
# Gateway型のVPC Endpointは無料で、データ転送料も発生しない
# プライベートサブネットからS3へのアクセスはこのEndpoint経由となる

resource "aws_vpc_endpoint" "s3" {
  count             = var.create_s3_endpoint ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-s3-endpoint"
    Type = "Gateway"
    Cost = "Free"
  })
}

# =============================================================================
# SSM Interface VPC Endpoints（有料: ~$0.01/hr/endpoint）
# =============================================================================
# Session Manager接続に必要な3つのEndpoint:
# - ssm: Systems Manager API
# - ssmmessages: Session Manager通信
# - ec2messages: EC2 Runコマンド
#
# 月額コスト: ~$22/月（3 endpoints × $0.01/hr × 720時間）

# SSM Endpoint
resource "aws_vpc_endpoint" "ssm" {
  count               = var.create_ssm_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ssm-endpoint"
    Type = "Interface"
    Cost = "~$0.01/hr"
  })
}

# SSM Messages Endpoint
resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.create_ssm_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ssmmessages-endpoint"
    Type = "Interface"
    Cost = "~$0.01/hr"
  })
}

# EC2 Messages Endpoint
resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.create_ssm_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ec2messages-endpoint"
    Type = "Interface"
    Cost = "~$0.01/hr"
  })
}
