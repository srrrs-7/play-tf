# =============================================================================
# VPC - Completely Private Network (No Internet Access)
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# =============================================================================
# Private Subnets (Application Tier - ECS runs here)
# =============================================================================

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  # No public IPs - completely private
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-private-${local.azs[count.index % length(local.azs)]}"
    Tier = "private"
  })
}

# =============================================================================
# VPC Endpoint Subnets (For Interface Endpoints)
# =============================================================================

resource "aws_subnet" "endpoint" {
  count = length(var.endpoint_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.endpoint_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  map_public_ip_on_launch = false

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-endpoint-${local.azs[count.index % length(local.azs)]}"
    Tier = "endpoint"
  })
}

# =============================================================================
# Route Tables - Private (No Internet Routes)
# =============================================================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # No routes to Internet Gateway or NAT Gateway
  # Routes will be added for:
  # - S3 Gateway Endpoint (automatically added)
  # - Transit Gateway (if enabled)

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "endpoint" {
  count = length(aws_subnet.endpoint)

  subnet_id      = aws_subnet.endpoint[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# VPC Flow Logs (Optional but recommended for troubleshooting)
# =============================================================================

resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_log.arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_log.arn
  max_aggregation_interval = 60

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-flow-log"
  })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-flow-log"
  })
}

resource "aws_iam_role" "flow_log" {
  name = "${local.name_prefix}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-flow-log-role"
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${local.name_prefix}-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}
