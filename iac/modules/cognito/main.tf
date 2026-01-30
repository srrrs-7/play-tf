# Cognito User Pool モジュール
# OAuth 2.0 認証フローをサポートする User Pool を作成

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = var.user_pool_name

  # ユーザー名属性の設定
  username_attributes      = var.username_attributes
  auto_verified_attributes = var.auto_verified_attributes

  # パスワードポリシー
  password_policy {
    minimum_length                   = var.password_policy.minimum_length
    require_lowercase                = var.password_policy.require_lowercase
    require_uppercase                = var.password_policy.require_uppercase
    require_numbers                  = var.password_policy.require_numbers
    require_symbols                  = var.password_policy.require_symbols
    temporary_password_validity_days = var.password_policy.temporary_password_validity_days
  }

  # MFA設定
  mfa_configuration = var.mfa_configuration

  # アカウント復旧設定
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # 管理者によるユーザー作成設定
  admin_create_user_config {
    allow_admin_create_user_only = var.allow_admin_create_user_only

    dynamic "invite_message_template" {
      for_each = var.invite_message_template != null ? [var.invite_message_template] : []
      content {
        email_message = invite_message_template.value.email_message
        email_subject = invite_message_template.value.email_subject
        sms_message   = invite_message_template.value.sms_message
      }
    }
  }

  # メール設定
  dynamic "email_configuration" {
    for_each = var.email_configuration != null ? [var.email_configuration] : []
    content {
      email_sending_account  = email_configuration.value.email_sending_account
      source_arn             = email_configuration.value.source_arn
      reply_to_email_address = email_configuration.value.reply_to_email_address
      from_email_address     = email_configuration.value.from_email_address
    }
  }

  # 検証メッセージテンプレート
  verification_message_template {
    default_email_option = var.verification_email_option
  }

  # ユーザー属性スキーマ
  dynamic "schema" {
    for_each = var.schema_attributes
    content {
      name                     = schema.value.name
      attribute_data_type      = schema.value.attribute_data_type
      mutable                  = lookup(schema.value, "mutable", true)
      required                 = lookup(schema.value, "required", false)
      developer_only_attribute = lookup(schema.value, "developer_only_attribute", false)

      dynamic "string_attribute_constraints" {
        for_each = schema.value.attribute_data_type == "String" && lookup(schema.value, "string_constraints", null) != null ? [schema.value.string_constraints] : []
        content {
          min_length = lookup(string_attribute_constraints.value, "min_length", null)
          max_length = lookup(string_attribute_constraints.value, "max_length", null)
        }
      }

      dynamic "number_attribute_constraints" {
        for_each = schema.value.attribute_data_type == "Number" && lookup(schema.value, "number_constraints", null) != null ? [schema.value.number_constraints] : []
        content {
          min_value = lookup(number_attribute_constraints.value, "min_value", null)
          max_value = lookup(number_attribute_constraints.value, "max_value", null)
        }
      }
    }
  }

  # Lambda トリガー
  dynamic "lambda_config" {
    for_each = var.lambda_config != null ? [var.lambda_config] : []
    content {
      pre_sign_up                    = lookup(lambda_config.value, "pre_sign_up", null)
      pre_authentication             = lookup(lambda_config.value, "pre_authentication", null)
      post_authentication            = lookup(lambda_config.value, "post_authentication", null)
      post_confirmation              = lookup(lambda_config.value, "post_confirmation", null)
      pre_token_generation           = lookup(lambda_config.value, "pre_token_generation", null)
      user_migration                 = lookup(lambda_config.value, "user_migration", null)
      custom_message                 = lookup(lambda_config.value, "custom_message", null)
      define_auth_challenge          = lookup(lambda_config.value, "define_auth_challenge", null)
      create_auth_challenge          = lookup(lambda_config.value, "create_auth_challenge", null)
      verify_auth_challenge_response = lookup(lambda_config.value, "verify_auth_challenge_response", null)
    }
  }

  tags = var.tags
}

# Cognito User Pool クライアント
resource "aws_cognito_user_pool_client" "this" {
  count = var.create_user_pool_client ? 1 : 0

  name         = var.user_pool_client_name
  user_pool_id = aws_cognito_user_pool.this.id

  # クライアントシークレット
  generate_secret = var.generate_client_secret

  # 認証フロー
  explicit_auth_flows = var.explicit_auth_flows

  # OAuth設定
  allowed_oauth_flows                  = var.allowed_oauth_flows
  allowed_oauth_flows_user_pool_client = var.allowed_oauth_flows_user_pool_client
  allowed_oauth_scopes                 = var.allowed_oauth_scopes
  supported_identity_providers         = var.supported_identity_providers

  # コールバックURL
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # トークン設定
  access_token_validity  = var.access_token_validity
  id_token_validity      = var.id_token_validity
  refresh_token_validity = var.refresh_token_validity

  token_validity_units {
    access_token  = var.token_validity_units.access_token
    id_token      = var.token_validity_units.id_token
    refresh_token = var.token_validity_units.refresh_token
  }

  # セキュリティ設定
  prevent_user_existence_errors = var.prevent_user_existence_errors

  # 読み取り/書き込み属性
  read_attributes  = var.read_attributes
  write_attributes = var.write_attributes
}

# Cognito User Pool ドメイン
resource "aws_cognito_user_pool_domain" "this" {
  count = var.create_user_pool_domain ? 1 : 0

  domain          = var.user_pool_domain
  user_pool_id    = aws_cognito_user_pool.this.id
  certificate_arn = var.domain_certificate_arn
}

# リソースサーバー（カスタムスコープ用）
resource "aws_cognito_resource_server" "this" {
  for_each = var.resource_servers

  identifier   = each.value.identifier
  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.this.id

  dynamic "scope" {
    for_each = lookup(each.value, "scopes", [])
    content {
      scope_name        = scope.value.scope_name
      scope_description = scope.value.scope_description
    }
  }
}
