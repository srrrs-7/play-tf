# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.create_cluster_role ? aws_iam_role.cluster[0].arn : var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = var.cluster_security_group_ids
  }

  dynamic "encryption_config" {
    for_each = var.cluster_encryption_config != null ? [var.cluster_encryption_config] : []
    content {
      provider {
        key_arn = encryption_config.value.provider_key_arn
      }
      resources = encryption_config.value.resources
    }
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  dynamic "kubernetes_network_config" {
    for_each = var.kubernetes_network_config != null ? [var.kubernetes_network_config] : []
    content {
      service_ipv4_cidr = lookup(kubernetes_network_config.value, "service_ipv4_cidr", null)
      ip_family         = lookup(kubernetes_network_config.value, "ip_family", "ipv4")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.cluster
  ]
}

# CloudWatch Log Group for EKS
resource "aws_cloudwatch_log_group" "cluster" {
  count = length(var.enabled_cluster_log_types) > 0 ? 1 : 0

  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_in_days
  kms_key_id        = var.cluster_log_kms_key_id

  tags = var.tags
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  count = var.create_cluster_role ? 1 : 0

  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  count = var.create_cluster_role ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster[0].name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  count = var.create_cluster_role ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster[0].name
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.value.name
  node_role_arn   = var.create_node_role ? aws_iam_role.node[0].arn : var.node_role_arn
  subnet_ids      = lookup(each.value, "subnet_ids", var.subnet_ids)

  instance_types = lookup(each.value, "instance_types", ["t3.medium"])
  capacity_type  = lookup(each.value, "capacity_type", "ON_DEMAND")
  disk_size      = lookup(each.value, "disk_size", 20)
  ami_type       = lookup(each.value, "ami_type", "AL2_x86_64")

  scaling_config {
    desired_size = lookup(each.value, "desired_size", 2)
    min_size     = lookup(each.value, "min_size", 1)
    max_size     = lookup(each.value, "max_size", 4)
  }

  dynamic "update_config" {
    for_each = lookup(each.value, "update_config", null) != null ? [each.value.update_config] : []
    content {
      max_unavailable            = lookup(update_config.value, "max_unavailable", null)
      max_unavailable_percentage = lookup(update_config.value, "max_unavailable_percentage", null)
    }
  }

  dynamic "launch_template" {
    for_each = lookup(each.value, "launch_template", null) != null ? [each.value.launch_template] : []
    content {
      id      = lookup(launch_template.value, "id", null)
      name    = lookup(launch_template.value, "name", null)
      version = launch_template.value.version
    }
  }

  dynamic "taint" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taint.value.key
      value  = lookup(taint.value, "value", null)
      effect = taint.value.effect
    }
  }

  labels = lookup(each.value, "labels", {})

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.value.name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly
  ]
}

# Node Group IAM Role
resource "aws_iam_role" "node" {
  count = var.create_node_role ? 1 : 0

  name = "${var.cluster_name}-node-role"

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

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  count = var.create_node_role ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  count = var.create_node_role ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  count = var.create_node_role ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node[0].name
}

# Additional Node IAM Policies
resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each = var.create_node_role ? toset(var.node_additional_policies) : []

  policy_arn = each.value
  role       = aws_iam_role.node[0].name
}

# Fargate Profile
resource "aws_eks_fargate_profile" "main" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = each.value.name
  pod_execution_role_arn = var.create_fargate_role ? aws_iam_role.fargate[0].arn : var.fargate_role_arn
  subnet_ids             = lookup(each.value, "subnet_ids", var.subnet_ids)

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = lookup(selector.value, "labels", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.value.name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.fargate_AmazonEKSFargatePodExecutionRolePolicy
  ]
}

# Fargate IAM Role
resource "aws_iam_role" "fargate" {
  count = var.create_fargate_role && length(var.fargate_profiles) > 0 ? 1 : 0

  name = "${var.cluster_name}-fargate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:eks:*:*:fargateprofile/${var.cluster_name}/*"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fargate_AmazonEKSFargatePodExecutionRolePolicy" {
  count = var.create_fargate_role && length(var.fargate_profiles) > 0 ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate[0].name
}

# EKS Add-ons
resource "aws_eks_addon" "main" {
  for_each = var.cluster_addons

  cluster_name = aws_eks_cluster.main.name
  addon_name   = each.key

  addon_version               = lookup(each.value, "addon_version", null)
  resolve_conflicts_on_create = lookup(each.value, "resolve_conflicts_on_create", "OVERWRITE")
  resolve_conflicts_on_update = lookup(each.value, "resolve_conflicts_on_update", "OVERWRITE")
  service_account_role_arn    = lookup(each.value, "service_account_role_arn", null)
  configuration_values        = lookup(each.value, "configuration_values", null)

  tags = var.tags

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_fargate_profile.main
  ]
}

# OIDC Provider
data "tls_certificate" "cluster" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# Cluster Security Group (additional)
resource "aws_security_group" "cluster_additional" {
  count = var.create_cluster_security_group ? 1 : 0

  name        = "${var.cluster_name}-cluster-additional-sg"
  description = "Additional security group for EKS cluster ${var.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-additional-sg"
    }
  )
}

resource "aws_security_group_rule" "cluster_additional_ingress" {
  for_each = var.create_cluster_security_group ? var.cluster_security_group_additional_rules : {}

  security_group_id        = aws_security_group.cluster_additional[0].id
  type                     = each.value.type
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = lookup(each.value, "cidr_blocks", null)
  source_security_group_id = lookup(each.value, "source_security_group_id", null)
  description              = lookup(each.value, "description", null)
}

# Node Security Group (additional)
resource "aws_security_group" "node_additional" {
  count = var.create_node_security_group ? 1 : 0

  name        = "${var.cluster_name}-node-additional-sg"
  description = "Additional security group for EKS nodes ${var.cluster_name}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-node-additional-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

resource "aws_security_group_rule" "node_additional_ingress" {
  for_each = var.create_node_security_group ? var.node_security_group_additional_rules : {}

  security_group_id        = aws_security_group.node_additional[0].id
  type                     = each.value.type
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = lookup(each.value, "cidr_blocks", null)
  source_security_group_id = lookup(each.value, "source_security_group_id", null)
  description              = lookup(each.value, "description", null)
}
