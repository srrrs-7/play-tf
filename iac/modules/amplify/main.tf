# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.name
  description = var.description

  # リポジトリ設定
  repository   = var.repository
  access_token = var.access_token
  oauth_token  = var.oauth_token

  # ビルド設定
  build_spec                  = var.build_spec
  enable_auto_branch_creation = var.enable_auto_branch_creation
  enable_branch_auto_build    = var.enable_branch_auto_build
  enable_branch_auto_deletion = var.enable_branch_auto_deletion
  enable_basic_auth           = var.enable_basic_auth
  basic_auth_credentials      = var.basic_auth_credentials

  # 環境変数
  environment_variables = var.environment_variables

  # IAM Service Role
  iam_service_role_arn = var.iam_service_role_arn

  # プラットフォーム（WEB または WEB_COMPUTE）
  platform = var.platform

  # 自動ブランチ作成設定
  dynamic "auto_branch_creation_config" {
    for_each = var.enable_auto_branch_creation && var.auto_branch_creation_config != null ? [var.auto_branch_creation_config] : []
    content {
      basic_auth_credentials        = lookup(auto_branch_creation_config.value, "basic_auth_credentials", null)
      build_spec                    = lookup(auto_branch_creation_config.value, "build_spec", null)
      enable_auto_build             = lookup(auto_branch_creation_config.value, "enable_auto_build", true)
      enable_basic_auth             = lookup(auto_branch_creation_config.value, "enable_basic_auth", false)
      enable_performance_mode       = lookup(auto_branch_creation_config.value, "enable_performance_mode", false)
      enable_pull_request_preview   = lookup(auto_branch_creation_config.value, "enable_pull_request_preview", false)
      environment_variables         = lookup(auto_branch_creation_config.value, "environment_variables", {})
      framework                     = lookup(auto_branch_creation_config.value, "framework", null)
      pull_request_environment_name = lookup(auto_branch_creation_config.value, "pull_request_environment_name", null)
      stage                         = lookup(auto_branch_creation_config.value, "stage", null)
    }
  }

  # 自動ブランチ作成パターン
  auto_branch_creation_patterns = var.auto_branch_creation_patterns

  # カスタムルール（リダイレクト、リライト）
  dynamic "custom_rule" {
    for_each = var.custom_rules
    content {
      source    = custom_rule.value.source
      target    = custom_rule.value.target
      status    = lookup(custom_rule.value, "status", null)
      condition = lookup(custom_rule.value, "condition", null)
    }
  }

  tags = var.tags
}

# Amplify Branch
resource "aws_amplify_branch" "this" {
  for_each = { for branch in var.branches : branch.branch_name => branch }

  app_id      = aws_amplify_app.this.id
  branch_name = each.value.branch_name

  # ブランチ設定
  description                   = lookup(each.value, "description", null)
  display_name                  = lookup(each.value, "display_name", null)
  enable_auto_build             = lookup(each.value, "enable_auto_build", true)
  enable_basic_auth             = lookup(each.value, "enable_basic_auth", false)
  basic_auth_credentials        = lookup(each.value, "basic_auth_credentials", null)
  enable_notification           = lookup(each.value, "enable_notification", false)
  enable_performance_mode       = lookup(each.value, "enable_performance_mode", false)
  enable_pull_request_preview   = lookup(each.value, "enable_pull_request_preview", false)
  environment_variables         = lookup(each.value, "environment_variables", {})
  framework                     = lookup(each.value, "framework", null)
  pull_request_environment_name = lookup(each.value, "pull_request_environment_name", null)
  stage                         = lookup(each.value, "stage", null)
  ttl                           = lookup(each.value, "ttl", null)

  # バックエンド環境ARN（Amplify Studio用）
  backend_environment_arn = lookup(each.value, "backend_environment_arn", null)

  tags = var.tags
}

# Amplify Domain Association
resource "aws_amplify_domain_association" "this" {
  for_each = { for domain in var.domain_associations : domain.domain_name => domain }

  app_id                 = aws_amplify_app.this.id
  domain_name            = each.value.domain_name
  enable_auto_sub_domain = lookup(each.value, "enable_auto_sub_domain", false)
  wait_for_verification  = lookup(each.value, "wait_for_verification", false)

  dynamic "sub_domain" {
    for_each = each.value.sub_domains
    content {
      branch_name = sub_domain.value.branch_name
      prefix      = sub_domain.value.prefix
    }
  }

  depends_on = [aws_amplify_branch.this]
}

# Amplify Webhook
resource "aws_amplify_webhook" "this" {
  for_each = { for webhook in var.webhooks : webhook.branch_name => webhook }

  app_id      = aws_amplify_app.this.id
  branch_name = each.value.branch_name
  description = lookup(each.value, "description", null)

  depends_on = [aws_amplify_branch.this]
}

# Backend Environment
resource "aws_amplify_backend_environment" "this" {
  for_each = { for env in var.backend_environments : env.environment_name => env }

  app_id           = aws_amplify_app.this.id
  environment_name = each.value.environment_name

  deployment_artifacts = lookup(each.value, "deployment_artifacts", null)
  stack_name           = lookup(each.value, "stack_name", null)
}
