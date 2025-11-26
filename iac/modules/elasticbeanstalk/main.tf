# Elastic Beanstalk Application
resource "aws_elastic_beanstalk_application" "main" {
  name        = var.application_name
  description = var.application_description

  dynamic "appversion_lifecycle" {
    for_each = var.appversion_lifecycle != null ? [var.appversion_lifecycle] : []
    content {
      service_role          = appversion_lifecycle.value.service_role
      max_count             = lookup(appversion_lifecycle.value, "max_count", null)
      max_age_in_days       = lookup(appversion_lifecycle.value, "max_age_in_days", null)
      delete_source_from_s3 = lookup(appversion_lifecycle.value, "delete_source_from_s3", false)
    }
  }

  tags = var.tags
}

# Elastic Beanstalk Environment
resource "aws_elastic_beanstalk_environment" "main" {
  name                = var.environment_name
  application         = aws_elastic_beanstalk_application.main.name
  solution_stack_name = var.solution_stack_name
  tier                = var.tier
  cname_prefix        = var.cname_prefix
  version_label       = var.version_label

  # VPC Configuration
  dynamic "setting" {
    for_each = var.vpc_id != null ? [1] : []
    content {
      namespace = "aws:ec2:vpc"
      name      = "VPCId"
      value     = var.vpc_id
    }
  }

  dynamic "setting" {
    for_each = length(var.subnet_ids) > 0 ? [1] : []
    content {
      namespace = "aws:ec2:vpc"
      name      = "Subnets"
      value     = join(",", var.subnet_ids)
    }
  }

  dynamic "setting" {
    for_each = length(var.elb_subnet_ids) > 0 ? [1] : []
    content {
      namespace = "aws:ec2:vpc"
      name      = "ELBSubnets"
      value     = join(",", var.elb_subnet_ids)
    }
  }

  dynamic "setting" {
    for_each = var.associate_public_ip_address != null ? [1] : []
    content {
      namespace = "aws:ec2:vpc"
      name      = "AssociatePublicIpAddress"
      value     = var.associate_public_ip_address
    }
  }

  # Instance Configuration
  dynamic "setting" {
    for_each = var.instance_type != null ? [1] : []
    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "InstanceType"
      value     = var.instance_type
    }
  }

  dynamic "setting" {
    for_each = var.create_instance_profile ? [1] : (var.instance_profile != null ? [1] : [])
    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "IamInstanceProfile"
      value     = var.create_instance_profile ? aws_iam_instance_profile.main[0].name : var.instance_profile
    }
  }

  dynamic "setting" {
    for_each = length(var.security_group_ids) > 0 ? [1] : []
    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "SecurityGroups"
      value     = join(",", var.security_group_ids)
    }
  }

  dynamic "setting" {
    for_each = var.key_name != null ? [1] : []
    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "EC2KeyName"
      value     = var.key_name
    }
  }

  dynamic "setting" {
    for_each = var.root_volume_size != null ? [1] : []
    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "RootVolumeSize"
      value     = var.root_volume_size
    }
  }

  dynamic "setting" {
    for_each = var.root_volume_type != null ? [1] : []
    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "RootVolumeType"
      value     = var.root_volume_type
    }
  }

  # Auto Scaling Configuration
  dynamic "setting" {
    for_each = var.min_instances != null ? [1] : []
    content {
      namespace = "aws:autoscaling:asg"
      name      = "MinSize"
      value     = var.min_instances
    }
  }

  dynamic "setting" {
    for_each = var.max_instances != null ? [1] : []
    content {
      namespace = "aws:autoscaling:asg"
      name      = "MaxSize"
      value     = var.max_instances
    }
  }

  # Environment Type
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = var.environment_type
  }

  dynamic "setting" {
    for_each = var.environment_type == "LoadBalanced" ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:environment"
      name      = "LoadBalancerType"
      value     = var.load_balancer_type
    }
  }

  # Service Role
  dynamic "setting" {
    for_each = var.create_service_role ? [1] : (var.service_role != null ? [1] : [])
    content {
      namespace = "aws:elasticbeanstalk:environment"
      name      = "ServiceRole"
      value     = var.create_service_role ? aws_iam_role.service[0].arn : var.service_role
    }
  }

  # Health Check
  dynamic "setting" {
    for_each = var.health_check_url != null ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:application"
      name      = "Application Healthcheck URL"
      value     = var.health_check_url
    }
  }

  # Enhanced Health Reporting
  dynamic "setting" {
    for_each = var.enhanced_reporting_enabled ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:healthreporting:system"
      name      = "SystemType"
      value     = "enhanced"
    }
  }

  # Managed Updates
  dynamic "setting" {
    for_each = var.managed_updates_enabled ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:managedactions"
      name      = "ManagedActionsEnabled"
      value     = "true"
    }
  }

  dynamic "setting" {
    for_each = var.managed_updates_enabled ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:managedactions"
      name      = "PreferredStartTime"
      value     = var.preferred_update_start_time
    }
  }

  dynamic "setting" {
    for_each = var.managed_updates_enabled ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:managedactions:platformupdate"
      name      = "UpdateLevel"
      value     = var.update_level
    }
  }

  # CloudWatch Logs
  dynamic "setting" {
    for_each = var.cloudwatch_logs_enabled ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:cloudwatch:logs"
      name      = "StreamLogs"
      value     = "true"
    }
  }

  dynamic "setting" {
    for_each = var.cloudwatch_logs_enabled ? [1] : []
    content {
      namespace = "aws:elasticbeanstalk:cloudwatch:logs"
      name      = "RetentionInDays"
      value     = var.cloudwatch_logs_retention_days
    }
  }

  # Environment Variables
  dynamic "setting" {
    for_each = var.environment_variables
    content {
      namespace = "aws:elasticbeanstalk:application:environment"
      name      = setting.key
      value     = setting.value
    }
  }

  # Additional Settings
  dynamic "setting" {
    for_each = var.additional_settings
    content {
      namespace = setting.value.namespace
      name      = setting.value.name
      value     = setting.value.value
      resource  = lookup(setting.value, "resource", null)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.environment_name
    }
  )
}

# Application Version
resource "aws_elastic_beanstalk_application_version" "main" {
  count = var.create_application_version ? 1 : 0

  name        = var.application_version_name
  application = aws_elastic_beanstalk_application.main.name
  description = var.application_version_description
  bucket      = var.application_version_bucket
  key         = var.application_version_key

  tags = var.tags
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "main" {
  count = var.create_instance_profile ? 1 : 0

  name = "${var.application_name}-instance-profile"
  role = aws_iam_role.instance[0].name

  tags = var.tags
}

resource "aws_iam_role" "instance" {
  count = var.create_instance_profile ? 1 : 0

  name = "${var.application_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "instance_web_tier" {
  count = var.create_instance_profile ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "instance_worker_tier" {
  count = var.create_instance_profile && var.tier == "Worker" ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "instance_multicontainer_docker" {
  count = var.create_instance_profile ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "instance_additional" {
  for_each = var.create_instance_profile ? toset(var.instance_additional_policies) : []

  role       = aws_iam_role.instance[0].name
  policy_arn = each.value
}

# Service Role
resource "aws_iam_role" "service" {
  count = var.create_service_role ? 1 : 0

  name = "${var.application_name}-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "elasticbeanstalk.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "elasticbeanstalk"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "service_enhanced_health" {
  count = var.create_service_role ? 1 : 0

  role       = aws_iam_role.service[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "service_managed_updates" {
  count = var.create_service_role && var.managed_updates_enabled ? 1 : 0

  role       = aws_iam_role.service[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}
