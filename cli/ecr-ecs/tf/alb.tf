# =============================================================================
# Application Load Balancer
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.stack_name}-alb"
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# =============================================================================
# Target Group
# =============================================================================
# Fargate用にtarget_type = "ip"を使用

resource "aws_lb_target_group" "main" {
  name        = "${var.stack_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    matcher             = "200-399"
  }

  deregistration_delay = var.deregistration_delay

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# HTTP Listener
# =============================================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-http-listener"
  })
}

# =============================================================================
# HTTPS Listener (Optional - requires ACM certificate)
# =============================================================================
# HTTPS対応が必要な場合は、ACM証明書を作成してこのリソースを有効化

# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = var.acm_certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.main.arn
#   }
#
#   tags = merge(local.common_tags, var.tags, {
#     Name = "${local.name_prefix}-https-listener"
#   })
# }

# =============================================================================
# HTTP to HTTPS Redirect (Optional)
# =============================================================================
# HTTPS有効時にHTTPをHTTPSにリダイレクト

# resource "aws_lb_listener" "http_redirect" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 80
#   protocol          = "HTTP"
#
#   default_action {
#     type = "redirect"
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }
# }
