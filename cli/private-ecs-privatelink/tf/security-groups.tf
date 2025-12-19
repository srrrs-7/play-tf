# =============================================================================
# Security Group for Internal ALB
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Internal ALB"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP from VPC
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow HTTPS from VPC (for future use)
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow from Transit Gateway networks (on-premises)
  dynamic "ingress" {
    for_each = var.enable_transit_gateway ? var.transit_gateway_cidr_blocks : []
    content {
      description = "HTTP from on-premises (${ingress.value})"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_transit_gateway ? var.transit_gateway_cidr_blocks : []
    content {
      description = "HTTPS from on-premises (${ingress.value})"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# =============================================================================
# Security Group for ECS Tasks
# =============================================================================

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from ALB
  ingress {
    description     = "Traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow traffic from NLB (for PrivateLink)
  dynamic "ingress" {
    for_each = var.enable_privatelink_service ? [1] : []
    content {
      description = "Traffic from NLB (PrivateLink)"
      from_port   = var.container_port
      to_port     = var.container_port
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  # Allow HTTPS to VPC Endpoints
  egress {
    description = "HTTPS to VPC Endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow to S3 Gateway Endpoint (via prefix list)
  egress {
    description     = "S3 Gateway Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3[0].prefix_list_id]
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ecs-tasks-sg"
  })
}

# =============================================================================
# Security Group for NLB (PrivateLink)
# =============================================================================

resource "aws_security_group" "nlb" {
  count = var.enable_privatelink_service ? 1 : 0

  name        = "${local.name_prefix}-nlb-sg"
  description = "Security group for NLB (PrivateLink)"
  vpc_id      = aws_vpc.main.id

  # Allow from anywhere (PrivateLink connections come from AWS network)
  ingress {
    description = "TCP from PrivateLink consumers"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from PrivateLink consumers"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-nlb-sg"
  })
}
