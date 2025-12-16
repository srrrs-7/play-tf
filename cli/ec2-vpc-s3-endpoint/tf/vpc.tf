# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # VPC Endpointsに必要
  enable_dns_support   = true # VPC Endpointsに必要

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# =============================================================================
# Public Subnet（NAT Instance用）
# =============================================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true # NAT InstanceにパブリックIPを付与

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-public"
    Type = "public"
  })
}

# =============================================================================
# Private Subnet（EC2用）
# =============================================================================

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = false # EC2にはパブリックIPを付与しない

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-private"
    Type = "private"
  })
}

# =============================================================================
# Public Route Table（IGW経由でインターネットへ）
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# Private Route Table（NAT Instance経由でインターネットへ）
# =============================================================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

# NAT Instance経由のルート（NAT Instance作成時のみ）
resource "aws_route" "private_nat" {
  count                  = var.create_nat_instance ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
