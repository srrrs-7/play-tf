# RDS Proxy
resource "aws_db_proxy" "this" {
  name                   = var.name
  debug_logging          = var.debug_logging
  engine_family          = var.engine_family
  idle_client_timeout    = var.idle_client_timeout
  require_tls            = var.require_tls
  role_arn               = var.role_arn
  vpc_security_group_ids = var.vpc_security_group_ids
  vpc_subnet_ids         = var.vpc_subnet_ids

  # 認証設定
  dynamic "auth" {
    for_each = var.auth_configs
    content {
      auth_scheme               = lookup(auth.value, "auth_scheme", "SECRETS")
      client_password_auth_type = lookup(auth.value, "client_password_auth_type", null)
      description               = lookup(auth.value, "description", null)
      iam_auth                  = lookup(auth.value, "iam_auth", "DISABLED")
      secret_arn                = auth.value.secret_arn
      username                  = lookup(auth.value, "username", null)
    }
  }

  tags = var.tags
}

# RDS Proxy Default Target Group
resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    connection_borrow_timeout    = var.connection_borrow_timeout
    init_query                   = var.init_query
    max_connections_percent      = var.max_connections_percent
    max_idle_connections_percent = var.max_idle_connections_percent
    session_pinning_filters      = var.session_pinning_filters
  }
}

# RDS Proxy Target (RDS Instance)
resource "aws_db_proxy_target" "instance" {
  for_each = { for target in var.db_instance_targets : target.db_instance_identifier => target }

  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = each.value.db_instance_identifier
}

# RDS Proxy Target (RDS Cluster)
resource "aws_db_proxy_target" "cluster" {
  for_each = { for target in var.db_cluster_targets : target.db_cluster_identifier => target }

  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
  db_cluster_identifier = each.value.db_cluster_identifier
}

# RDS Proxy Endpoint (追加エンドポイント)
resource "aws_db_proxy_endpoint" "this" {
  for_each = { for endpoint in var.proxy_endpoints : endpoint.name => endpoint }

  db_proxy_name          = aws_db_proxy.this.name
  db_proxy_endpoint_name = each.value.name
  vpc_subnet_ids         = lookup(each.value, "vpc_subnet_ids", var.vpc_subnet_ids)
  vpc_security_group_ids = lookup(each.value, "vpc_security_group_ids", var.vpc_security_group_ids)
  target_role            = lookup(each.value, "target_role", "READ_WRITE")

  tags = var.tags
}
