# AppSync GraphQL API
resource "aws_appsync_graphql_api" "this" {
  name                = var.name
  authentication_type = var.authentication_type
  schema              = var.schema

  # 追加の認証プロバイダー
  dynamic "additional_authentication_provider" {
    for_each = var.additional_authentication_providers
    content {
      authentication_type = additional_authentication_provider.value.authentication_type

      dynamic "lambda_authorizer_config" {
        for_each = additional_authentication_provider.value.authentication_type == "AWS_LAMBDA" ? [1] : []
        content {
          authorizer_uri                   = additional_authentication_provider.value.lambda_authorizer_uri
          authorizer_result_ttl_in_seconds = lookup(additional_authentication_provider.value, "authorizer_result_ttl_in_seconds", 300)
          identity_validation_expression   = lookup(additional_authentication_provider.value, "identity_validation_expression", null)
        }
      }

      dynamic "openid_connect_config" {
        for_each = additional_authentication_provider.value.authentication_type == "OPENID_CONNECT" ? [1] : []
        content {
          issuer    = additional_authentication_provider.value.oidc_issuer
          client_id = lookup(additional_authentication_provider.value, "oidc_client_id", null)
          auth_ttl  = lookup(additional_authentication_provider.value, "oidc_auth_ttl", null)
          iat_ttl   = lookup(additional_authentication_provider.value, "oidc_iat_ttl", null)
        }
      }

      dynamic "user_pool_config" {
        for_each = additional_authentication_provider.value.authentication_type == "AMAZON_COGNITO_USER_POOLS" ? [1] : []
        content {
          user_pool_id        = additional_authentication_provider.value.user_pool_id
          aws_region          = lookup(additional_authentication_provider.value, "user_pool_region", null)
          app_id_client_regex = lookup(additional_authentication_provider.value, "app_id_client_regex", null)
        }
      }
    }
  }

  # Lambda認証設定
  dynamic "lambda_authorizer_config" {
    for_each = var.authentication_type == "AWS_LAMBDA" ? [1] : []
    content {
      authorizer_uri                   = var.lambda_authorizer_uri
      authorizer_result_ttl_in_seconds = var.lambda_authorizer_result_ttl_in_seconds
      identity_validation_expression   = var.lambda_identity_validation_expression
    }
  }

  # OpenID Connect設定
  dynamic "openid_connect_config" {
    for_each = var.authentication_type == "OPENID_CONNECT" ? [1] : []
    content {
      issuer    = var.oidc_issuer
      client_id = var.oidc_client_id
      auth_ttl  = var.oidc_auth_ttl
      iat_ttl   = var.oidc_iat_ttl
    }
  }

  # Cognito User Pool設定
  dynamic "user_pool_config" {
    for_each = var.authentication_type == "AMAZON_COGNITO_USER_POOLS" ? [1] : []
    content {
      user_pool_id        = var.user_pool_id
      aws_region          = var.user_pool_region
      app_id_client_regex = var.app_id_client_regex
      default_action      = var.user_pool_default_action
    }
  }

  # ロギング設定
  dynamic "log_config" {
    for_each = var.logging_enabled ? [1] : []
    content {
      cloudwatch_logs_role_arn = var.cloudwatch_logs_role_arn
      field_log_level          = var.field_log_level
      exclude_verbose_content  = var.exclude_verbose_content
    }
  }

  # X-Ray トレーシング
  xray_enabled = var.xray_enabled

  # イントロスペクション設定
  introspection_config = var.introspection_config

  # クエリ深度制限
  query_depth_limit = var.query_depth_limit

  # リゾルバカウント制限
  resolver_count_limit = var.resolver_count_limit

  # 可視性設定
  visibility = var.visibility

  tags = var.tags
}

# API Key（API_KEY認証の場合）
resource "aws_appsync_api_key" "this" {
  count = var.authentication_type == "API_KEY" || var.create_api_key ? 1 : 0

  api_id      = aws_appsync_graphql_api.this.id
  description = var.api_key_description
  expires     = var.api_key_expires
}

# DynamoDB Data Source
resource "aws_appsync_datasource" "dynamodb" {
  for_each = { for ds in var.dynamodb_datasources : ds.name => ds }

  api_id           = aws_appsync_graphql_api.this.id
  name             = each.value.name
  type             = "AMAZON_DYNAMODB"
  service_role_arn = each.value.service_role_arn

  dynamodb_config {
    table_name             = each.value.table_name
    region                 = lookup(each.value, "region", null)
    use_caller_credentials = lookup(each.value, "use_caller_credentials", false)
    versioned              = lookup(each.value, "versioned", false)

    dynamic "delta_sync_config" {
      for_each = lookup(each.value, "delta_sync_enabled", false) ? [1] : []
      content {
        base_table_ttl       = each.value.base_table_ttl
        delta_sync_table_ttl = each.value.delta_sync_table_ttl
        delta_sync_table_name = each.value.delta_sync_table_name
      }
    }
  }
}

# Lambda Data Source
resource "aws_appsync_datasource" "lambda" {
  for_each = { for ds in var.lambda_datasources : ds.name => ds }

  api_id           = aws_appsync_graphql_api.this.id
  name             = each.value.name
  type             = "AWS_LAMBDA"
  service_role_arn = each.value.service_role_arn

  lambda_config {
    function_arn = each.value.function_arn
  }
}

# HTTP Data Source
resource "aws_appsync_datasource" "http" {
  for_each = { for ds in var.http_datasources : ds.name => ds }

  api_id           = aws_appsync_graphql_api.this.id
  name             = each.value.name
  type             = "HTTP"
  service_role_arn = lookup(each.value, "service_role_arn", null)

  http_config {
    endpoint = each.value.endpoint

    dynamic "authorization_config" {
      for_each = lookup(each.value, "authorization_type", null) != null ? [1] : []
      content {
        authorization_type = each.value.authorization_type

        dynamic "aws_iam_config" {
          for_each = each.value.authorization_type == "AWS_IAM" ? [1] : []
          content {
            signing_region       = lookup(each.value, "signing_region", null)
            signing_service_name = lookup(each.value, "signing_service_name", null)
          }
        }
      }
    }
  }
}

# None Data Source (ローカルリゾルバ用)
resource "aws_appsync_datasource" "none" {
  for_each = { for ds in var.none_datasources : ds.name => ds }

  api_id      = aws_appsync_graphql_api.this.id
  name        = each.value.name
  type        = "NONE"
  description = lookup(each.value, "description", null)
}

# Resolvers
resource "aws_appsync_resolver" "this" {
  for_each = { for r in var.resolvers : "${r.type}.${r.field}" => r }

  api_id = aws_appsync_graphql_api.this.id
  type   = each.value.type
  field  = each.value.field

  # データソース（パイプラインでない場合）
  data_source = lookup(each.value, "pipeline_config", null) == null ? each.value.data_source : null

  # VTLリクエストマッピングテンプレート
  request_template  = lookup(each.value, "request_template", null)
  response_template = lookup(each.value, "response_template", null)

  # JavaScriptランタイム
  dynamic "runtime" {
    for_each = lookup(each.value, "runtime_name", null) != null ? [1] : []
    content {
      name            = each.value.runtime_name
      runtime_version = each.value.runtime_version
    }
  }

  code = lookup(each.value, "code", null)

  # パイプラインリゾルバ
  kind = lookup(each.value, "pipeline_config", null) != null ? "PIPELINE" : "UNIT"

  dynamic "pipeline_config" {
    for_each = lookup(each.value, "pipeline_config", null) != null ? [1] : []
    content {
      functions = each.value.pipeline_config.functions
    }
  }

  # キャッシュ設定
  caching_config {
    caching_keys = lookup(each.value, "caching_keys", [])
    ttl          = lookup(each.value, "caching_ttl", 0)
  }

  # 最大バッチサイズ
  max_batch_size = lookup(each.value, "max_batch_size", null)
}

# Functions (パイプライン用)
resource "aws_appsync_function" "this" {
  for_each = { for f in var.functions : f.name => f }

  api_id      = aws_appsync_graphql_api.this.id
  name        = each.value.name
  data_source = each.value.data_source

  # VTLテンプレート
  request_mapping_template  = lookup(each.value, "request_mapping_template", null)
  response_mapping_template = lookup(each.value, "response_mapping_template", null)

  # JavaScriptランタイム
  dynamic "runtime" {
    for_each = lookup(each.value, "runtime_name", null) != null ? [1] : []
    content {
      name            = each.value.runtime_name
      runtime_version = each.value.runtime_version
    }
  }

  code = lookup(each.value, "code", null)

  description                  = lookup(each.value, "description", null)
  function_version             = lookup(each.value, "function_version", "2018-05-29")
  max_batch_size               = lookup(each.value, "max_batch_size", null)
}
