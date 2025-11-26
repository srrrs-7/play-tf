# App Runner Service
resource "aws_apprunner_service" "main" {
  service_name = var.service_name

  source_configuration {
    auto_deployments_enabled = var.auto_deployments_enabled

    # ECR source
    dynamic "image_repository" {
      for_each = var.source_type == "ecr" ? [var.image_repository] : []
      content {
        image_identifier      = image_repository.value.image_identifier
        image_repository_type = lookup(image_repository.value, "image_repository_type", "ECR")

        image_configuration {
          port                          = lookup(image_repository.value.image_configuration, "port", "8080")
          runtime_environment_variables = lookup(image_repository.value.image_configuration, "runtime_environment_variables", {})
          runtime_environment_secrets   = lookup(image_repository.value.image_configuration, "runtime_environment_secrets", {})
          start_command                 = lookup(image_repository.value.image_configuration, "start_command", null)
        }
      }
    }

    # Code source
    dynamic "code_repository" {
      for_each = var.source_type == "code" ? [var.code_repository] : []
      content {
        repository_url = code_repository.value.repository_url

        source_code_version {
          type  = lookup(code_repository.value.source_code_version, "type", "BRANCH")
          value = code_repository.value.source_code_version.value
        }

        code_configuration {
          configuration_source = lookup(code_repository.value.code_configuration, "configuration_source", "API")

          dynamic "code_configuration_values" {
            for_each = lookup(code_repository.value.code_configuration, "configuration_source", "API") == "API" ? [code_repository.value.code_configuration.code_configuration_values] : []
            content {
              runtime                       = code_configuration_values.value.runtime
              build_command                 = lookup(code_configuration_values.value, "build_command", null)
              start_command                 = lookup(code_configuration_values.value, "start_command", null)
              port                          = lookup(code_configuration_values.value, "port", "8080")
              runtime_environment_variables = lookup(code_configuration_values.value, "runtime_environment_variables", {})
              runtime_environment_secrets   = lookup(code_configuration_values.value, "runtime_environment_secrets", {})
            }
          }
        }

        dynamic "source_directory" {
          for_each = lookup(code_repository.value, "source_directory", null) != null ? [code_repository.value.source_directory] : []
          content {
            # Source directory path
          }
        }
      }
    }

    # Authentication configuration for ECR or GitHub
    dynamic "authentication_configuration" {
      for_each = var.authentication_configuration != null ? [var.authentication_configuration] : []
      content {
        access_role_arn = lookup(authentication_configuration.value, "access_role_arn", null)
        connection_arn  = lookup(authentication_configuration.value, "connection_arn", null)
      }
    }
  }

  instance_configuration {
    cpu               = var.cpu
    memory            = var.memory
    instance_role_arn = var.create_instance_role ? aws_iam_role.instance[0].arn : var.instance_role_arn
  }

  dynamic "health_check_configuration" {
    for_each = var.health_check_configuration != null ? [var.health_check_configuration] : []
    content {
      protocol            = lookup(health_check_configuration.value, "protocol", "TCP")
      path                = lookup(health_check_configuration.value, "path", "/")
      interval            = lookup(health_check_configuration.value, "interval", 5)
      timeout             = lookup(health_check_configuration.value, "timeout", 2)
      healthy_threshold   = lookup(health_check_configuration.value, "healthy_threshold", 1)
      unhealthy_threshold = lookup(health_check_configuration.value, "unhealthy_threshold", 5)
    }
  }

  dynamic "network_configuration" {
    for_each = var.network_configuration != null ? [var.network_configuration] : []
    content {
      ingress_configuration {
        is_publicly_accessible = lookup(network_configuration.value, "is_publicly_accessible", true)
      }

      dynamic "egress_configuration" {
        for_each = lookup(network_configuration.value, "egress_configuration", null) != null ? [network_configuration.value.egress_configuration] : []
        content {
          egress_type       = lookup(egress_configuration.value, "egress_type", "DEFAULT")
          vpc_connector_arn = lookup(egress_configuration.value, "vpc_connector_arn", null)
        }
      }

      dynamic "ip_address_type" {
        for_each = lookup(network_configuration.value, "ip_address_type", null) != null ? [1] : []
        content {
        }
      }
    }
  }

  dynamic "observability_configuration" {
    for_each = var.observability_configuration_arn != null ? [1] : []
    content {
      observability_enabled           = true
      observability_configuration_arn = var.observability_configuration_arn
    }
  }

  auto_scaling_configuration_arn = var.create_auto_scaling_configuration ? aws_apprunner_auto_scaling_configuration_version.main[0].arn : var.auto_scaling_configuration_arn

  dynamic "encryption_configuration" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      kms_key = var.kms_key_arn
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.service_name
    }
  )
}

# Auto Scaling Configuration
resource "aws_apprunner_auto_scaling_configuration_version" "main" {
  count = var.create_auto_scaling_configuration ? 1 : 0

  auto_scaling_configuration_name = "${var.service_name}-autoscaling"
  max_concurrency                 = var.auto_scaling_max_concurrency
  max_size                        = var.auto_scaling_max_size
  min_size                        = var.auto_scaling_min_size

  tags = var.tags
}

# VPC Connector
resource "aws_apprunner_vpc_connector" "main" {
  count = var.create_vpc_connector ? 1 : 0

  vpc_connector_name = "${var.service_name}-vpc-connector"
  subnets            = var.vpc_connector_subnets
  security_groups    = var.vpc_connector_security_groups

  tags = var.tags
}

# ECR Access Role
resource "aws_iam_role" "ecr_access" {
  count = var.create_ecr_access_role && var.source_type == "ecr" ? 1 : 0

  name = "${var.service_name}-ecr-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "build.apprunner.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  count = var.create_ecr_access_role && var.source_type == "ecr" ? 1 : 0

  role       = aws_iam_role.ecr_access[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# Instance Role
resource "aws_iam_role" "instance" {
  count = var.create_instance_role ? 1 : 0

  name = "${var.service_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "tasks.apprunner.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "instance" {
  count = var.create_instance_role && length(var.instance_policy_statements) > 0 ? 1 : 0

  name = "${var.service_name}-instance-policy"
  role = aws_iam_role.instance[0].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.instance_policy_statements
  })
}

resource "aws_iam_role_policy_attachment" "instance_additional" {
  for_each = var.create_instance_role ? toset(var.instance_additional_policies) : []

  role       = aws_iam_role.instance[0].name
  policy_arn = each.value
}

# GitHub Connection (if needed)
resource "aws_apprunner_connection" "github" {
  count = var.create_github_connection ? 1 : 0

  connection_name = "${var.service_name}-github-connection"
  provider_type   = "GITHUB"

  tags = var.tags
}

# Observability Configuration
resource "aws_apprunner_observability_configuration" "main" {
  count = var.create_observability_configuration ? 1 : 0

  observability_configuration_name = "${var.service_name}-observability"

  trace_configuration {
    vendor = "AWSXRAY"
  }

  tags = var.tags
}

# Custom Domain Association
resource "aws_apprunner_custom_domain_association" "main" {
  for_each = var.custom_domains

  service_arn          = aws_apprunner_service.main.arn
  domain_name          = each.value.domain_name
  enable_www_subdomain = lookup(each.value, "enable_www_subdomain", true)
}
