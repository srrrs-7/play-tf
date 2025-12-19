# =============================================================================
# Internal Application Load Balancer
# =============================================================================
# This ALB is internal-only (not internet-facing)
# It can be exposed via:
# - VPC Endpoint Service (PrivateLink) for cross-VPC/cross-account access
# - Transit Gateway for on-premises access via Direct Connect
# =============================================================================

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = true  # Internal ALB - not internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private[*].id

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.alb_idle_timeout

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "${local.name_prefix}-alb"
      enabled = true
    }
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# =============================================================================
# Target Group
# =============================================================================

resource "aws_lb_target_group" "main" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = var.health_check_interval
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# HTTP Listener
# =============================================================================

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-listener"
  })
}

# =============================================================================
# HTTPS Listener (Optional - requires certificate)
# =============================================================================
# Uncomment and configure if you need HTTPS
#
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = var.certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.main.arn
#   }
# }
