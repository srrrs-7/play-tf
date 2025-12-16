# =============================================================================
# ALB Security Group
# =============================================================================
# インターネットからHTTP/HTTPSトラフィックを許可

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for ALB - allows HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# HTTP (80) from anywhere
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "http-from-internet"
  }
}

# HTTPS (443) from anywhere
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "https-from-internet"
  }
}

# Egress: All traffic
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}

# =============================================================================
# ECS Security Group
# =============================================================================
# ALBからのトラフィックのみ許可

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Security group for ECS tasks - allows traffic from ALB only"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecs-sg"
  })
}

# Container port from ALB
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Container port from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.alb.id

  tags = {
    Name = "container-port-from-alb"
  }
}

# Egress: All traffic (for ECR pull, etc.)
resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}
