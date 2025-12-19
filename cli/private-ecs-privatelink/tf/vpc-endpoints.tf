# =============================================================================
# VPC Endpoints - PrivateLink for AWS Services
# =============================================================================
# Required endpoints for ECS Fargate in a completely private network:
# - ecr.api: ECR API calls
# - ecr.dkr: Docker Registry (pull images)
# - s3: S3 access (ECR image layers stored in S3)
# - logs: CloudWatch Logs
# - ecs-agent, ecs-telemetry, ecs: ECS control plane
# - ssm, ssmmessages, ec2messages: ECS Exec support
# =============================================================================

# =============================================================================
# Security Group for Interface Endpoints
# =============================================================================

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })
}

# =============================================================================
# S3 Gateway Endpoint (Required for ECR image layers)
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}

# =============================================================================
# ECR Endpoints (Required for pulling container images)
# =============================================================================

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ecr-dkr-endpoint"
  })
}

# =============================================================================
# CloudWatch Logs Endpoint (Required for container logging)
# =============================================================================

resource "aws_vpc_endpoint" "logs" {
  count = var.enable_logs_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-logs-endpoint"
  })
}

# =============================================================================
# ECS Endpoints (Required for ECS control plane communication)
# =============================================================================

resource "aws_vpc_endpoint" "ecs" {
  count = var.enable_ecs_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ecs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ecs-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecs_agent" {
  count = var.enable_ecs_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ecs-agent"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ecs-agent-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecs_telemetry" {
  count = var.enable_ecs_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ecs-telemetry"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ecs-telemetry-endpoint"
  })
}

# =============================================================================
# SSM Endpoints (Required for ECS Exec)
# =============================================================================

resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_ssm_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ssm-endpoint"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.enable_ssm_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ssmmessages-endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  count = var.enable_ssm_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-ec2messages-endpoint"
  })
}

# =============================================================================
# Secrets Manager Endpoint (Optional - for secrets)
# =============================================================================

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_secrets_manager_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-secretsmanager-endpoint"
  })
}

# =============================================================================
# KMS Endpoint (Optional - for encryption)
# =============================================================================

resource "aws_vpc_endpoint" "kms" {
  count = var.enable_kms_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoint[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-kms-endpoint"
  })
}
