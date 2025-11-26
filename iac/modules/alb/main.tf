# Application Load Balancer
resource "aws_lb" "main" {
  name               = var.alb_name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = var.enable_http2
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = var.drop_invalid_header_fields

  dynamic "access_logs" {
    for_each = var.access_logs != null ? [var.access_logs] : []
    content {
      bucket  = access_logs.value.bucket
      prefix  = lookup(access_logs.value, "prefix", "")
      enabled = lookup(access_logs.value, "enabled", true)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.alb_name
    }
  )
}

# Target Group
resource "aws_lb_target_group" "main" {
  for_each = var.target_groups

  name                          = each.value.name
  port                          = each.value.port
  protocol                      = lookup(each.value, "protocol", "HTTP")
  protocol_version              = lookup(each.value, "protocol_version", "HTTP1")
  vpc_id                        = var.vpc_id
  target_type                   = lookup(each.value, "target_type", "instance")
  deregistration_delay          = lookup(each.value, "deregistration_delay", 300)
  slow_start                    = lookup(each.value, "slow_start", 0)
  load_balancing_algorithm_type = lookup(each.value, "load_balancing_algorithm_type", "round_robin")

  health_check {
    enabled             = lookup(each.value.health_check, "enabled", true)
    healthy_threshold   = lookup(each.value.health_check, "healthy_threshold", 3)
    unhealthy_threshold = lookup(each.value.health_check, "unhealthy_threshold", 3)
    timeout             = lookup(each.value.health_check, "timeout", 5)
    interval            = lookup(each.value.health_check, "interval", 30)
    path                = lookup(each.value.health_check, "path", "/")
    port                = lookup(each.value.health_check, "port", "traffic-port")
    protocol            = lookup(each.value.health_check, "protocol", "HTTP")
    matcher             = lookup(each.value.health_check, "matcher", "200")
  }

  dynamic "stickiness" {
    for_each = lookup(each.value, "stickiness", null) != null ? [each.value.stickiness] : []
    content {
      type            = stickiness.value.type
      cookie_duration = lookup(stickiness.value, "cookie_duration", 86400)
      cookie_name     = lookup(stickiness.value, "cookie_name", null)
      enabled         = lookup(stickiness.value, "enabled", true)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP Listener (redirect to HTTPS or forward)
resource "aws_lb_listener" "http" {
  count = var.create_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.http_listener_redirect_to_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.http_listener_redirect_to_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.http_listener_redirect_to_https ? null : (
      length(var.target_groups) > 0 ? aws_lb_target_group.main[keys(var.target_groups)[0]].arn : null
    )
  }

  tags = var.tags
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  count = var.create_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = length(var.target_groups) > 0 ? aws_lb_target_group.main[keys(var.target_groups)[0]].arn : null
  }

  tags = var.tags
}

# Additional Certificates for HTTPS Listener
resource "aws_lb_listener_certificate" "additional" {
  for_each = var.create_https_listener && length(var.additional_certificate_arns) > 0 ? toset(var.additional_certificate_arns) : []

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

# Listener Rules
resource "aws_lb_listener_rule" "main" {
  for_each = var.listener_rules

  listener_arn = each.value.listener_type == "https" ? (
    var.create_https_listener ? aws_lb_listener.https[0].arn : null
    ) : (
    var.create_http_listener ? aws_lb_listener.http[0].arn : null
  )
  priority = each.value.priority

  action {
    type             = lookup(each.value, "action_type", "forward")
    target_group_arn = lookup(each.value, "target_group_key", null) != null ? aws_lb_target_group.main[each.value.target_group_key].arn : null

    dynamic "redirect" {
      for_each = lookup(each.value, "action_type", "forward") == "redirect" ? [each.value.redirect] : []
      content {
        host        = lookup(redirect.value, "host", "#{host}")
        path        = lookup(redirect.value, "path", "/#{path}")
        port        = lookup(redirect.value, "port", "#{port}")
        protocol    = lookup(redirect.value, "protocol", "#{protocol}")
        query       = lookup(redirect.value, "query", "#{query}")
        status_code = lookup(redirect.value, "status_code", "HTTP_301")
      }
    }

    dynamic "fixed_response" {
      for_each = lookup(each.value, "action_type", "forward") == "fixed-response" ? [each.value.fixed_response] : []
      content {
        content_type = fixed_response.value.content_type
        message_body = lookup(fixed_response.value, "message_body", null)
        status_code  = lookup(fixed_response.value, "status_code", "200")
      }
    }
  }

  dynamic "condition" {
    for_each = lookup(each.value, "host_headers", null) != null ? [1] : []
    content {
      host_header {
        values = each.value.host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = lookup(each.value, "path_patterns", null) != null ? [1] : []
    content {
      path_pattern {
        values = each.value.path_patterns
      }
    }
  }

  dynamic "condition" {
    for_each = lookup(each.value, "http_headers", null) != null ? each.value.http_headers : []
    content {
      http_header {
        http_header_name = condition.value.name
        values           = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = lookup(each.value, "source_ips", null) != null ? [1] : []
    content {
      source_ip {
        values = each.value.source_ips
      }
    }
  }

  tags = var.tags
}

# Security Group for ALB (optional)
resource "aws_security_group" "alb" {
  count = var.create_security_group ? 1 : 0

  name        = "${var.alb_name}-sg"
  description = "Security group for ${var.alb_name} ALB"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.security_group_ingress_rules
    content {
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = lookup(ingress.value, "cidr_blocks", null)
      ipv6_cidr_blocks = lookup(ingress.value, "ipv6_cidr_blocks", null)
      security_groups  = lookup(ingress.value, "security_groups", null)
      description      = lookup(ingress.value, "description", null)
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.alb_name}-sg"
    }
  )
}
