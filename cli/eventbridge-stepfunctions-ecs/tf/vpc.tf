# =============================================================================
# VPC (Optional - only when use_default_vpc = false)
# =============================================================================

resource "aws_vpc" "main" {
  count = var.use_default_vpc ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  count = var.use_default_vpc ? 0 : 1

  vpc_id = aws_vpc.main[0].id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# =============================================================================
# Public Subnets
# =============================================================================

resource "aws_subnet" "public" {
  count = var.use_default_vpc ? 0 : length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Type = "public"
  })
}

# =============================================================================
# Route Table
# =============================================================================

resource "aws_route_table" "public" {
  count = var.use_default_vpc ? 0 : 1

  vpc_id = aws_vpc.main[0].id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  count = var.use_default_vpc ? 0 : 1

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route_table_association" "public" {
  count = var.use_default_vpc ? 0 : length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# =============================================================================
# ECS Security Group
# =============================================================================

resource "aws_security_group" "ecs" {
  count = var.use_default_vpc ? 0 : 1

  name        = "${local.name_prefix}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main[0].id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecs-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  count = var.use_default_vpc ? 0 : 1

  security_group_id = aws_security_group.ecs[0].id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}
