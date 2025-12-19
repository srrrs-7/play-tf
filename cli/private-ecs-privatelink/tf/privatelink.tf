# =============================================================================
# VPC Endpoint Service (PrivateLink Provider)
# =============================================================================
# This creates a VPC Endpoint Service that allows other VPCs/accounts
# to connect to the Internal ALB via PrivateLink.
#
# Consumer VPCs can create Interface Endpoints to connect to this service.
# =============================================================================

resource "aws_vpc_endpoint_service" "main" {
  count = var.enable_privatelink_service ? 1 : 0

  acceptance_required        = var.privatelink_acceptance_required
  network_load_balancer_arns = [aws_lb.nlb[0].arn]

  allowed_principals = var.privatelink_allowed_principals

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-vpce-service"
  })
}

# =============================================================================
# Network Load Balancer (Required for VPC Endpoint Service)
# =============================================================================
# VPC Endpoint Service requires NLB (not ALB)
# NLB forwards traffic to ALB Target Group
# =============================================================================

resource "aws_lb" "nlb" {
  count = var.enable_privatelink_service ? 1 : 0

  name               = "${local.name_prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.enable_deletion_protection

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-nlb"
  })
}

resource "aws_lb_target_group" "nlb" {
  count = var.enable_privatelink_service ? 1 : 0

  name        = "${local.name_prefix}-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "alb"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    protocol            = "HTTP"
    path                = var.health_check_path
    matcher             = "200-299"
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-nlb-tg"
  })
}

resource "aws_lb_target_group_attachment" "nlb_alb" {
  count = var.enable_privatelink_service ? 1 : 0

  target_group_arn = aws_lb_target_group.nlb[0].arn
  target_id        = aws_lb.main.arn
  port             = 80
}

resource "aws_lb_listener" "nlb" {
  count = var.enable_privatelink_service ? 1 : 0

  load_balancer_arn = aws_lb.nlb[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb[0].arn
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-nlb-listener"
  })
}

# =============================================================================
# VPC Endpoint Service Notification (Optional)
# =============================================================================

resource "aws_sns_topic" "endpoint_notifications" {
  count = var.enable_privatelink_service ? 1 : 0

  name = "${local.name_prefix}-endpoint-notifications"

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-endpoint-notifications"
  })
}

resource "aws_vpc_endpoint_connection_notification" "main" {
  count = var.enable_privatelink_service ? 1 : 0

  vpc_endpoint_service_id     = aws_vpc_endpoint_service.main[0].id
  connection_notification_arn = aws_sns_topic.endpoint_notifications[0].arn
  connection_events           = ["Accept", "Reject", "Connect", "Delete"]
}

# =============================================================================
# Example: Consumer VPC Endpoint (commented out - for reference)
# =============================================================================
# This shows how a consumer VPC would connect to the service
#
# resource "aws_vpc_endpoint" "consumer_endpoint" {
#   vpc_id              = "vpc-consumer123"
#   service_name        = aws_vpc_endpoint_service.main[0].service_name
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = ["subnet-consumer1", "subnet-consumer2"]
#   security_group_ids  = ["sg-consumer"]
#   private_dns_enabled = false
# }
