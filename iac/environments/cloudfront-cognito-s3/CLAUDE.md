# CLAUDE.md - CloudFront + Cognito + S3 Environment

This environment provides a CloudFront distribution with Cognito authentication for protected S3 content delivery.

## Overview

This environment deploys a secure content delivery architecture using CloudFront with Lambda@Edge functions that enforce Cognito authentication. Users must authenticate via Cognito Hosted UI before accessing protected S3 content.

## Architecture

```
Browser
  |
  | (1) GET /content.jpg
  v
CloudFront Distribution
  |
  | (2) Lambda@Edge checks JWT cookie
  |     - Valid: proceed to S3
  |     - Invalid: redirect to Cognito login
  v
Cognito Hosted UI (if unauthenticated)
  |
  | (3) User authenticates
  v
Lambda@Edge: auth-callback
  |
  | (4) Exchange code for tokens, set cookies
  v
S3 Bucket (private, OAC)
  |
  v
Protected Content
```

## Modules Used

- `s3` - S3 bucket for content storage (private access via OAC)
- `cognito` - Cognito User Pool with Hosted UI for authentication

## Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| S3 Bucket | `{project_name}-{env}-content` | Protected content storage |
| Cognito User Pool | `{project_name}-{env}-users` | User authentication |
| Cognito User Pool Client | `{project_name}-{env}-client` | OAuth client |
| CloudFront Distribution | - | Content delivery with auth |
| Lambda@Edge | `{project_name}-{env}-auth-check` | JWT validation |
| Lambda@Edge | `{project_name}-{env}-auth-callback` | OAuth callback handler |
| Lambda@Edge | `{project_name}-{env}-auth-refresh` | Token refresh |
| CloudFront OAC | `{project_name}-{env}-oac` | S3 access control |
| CloudWatch Log Groups | `/aws/lambda/us-east-1.*` | Lambda@Edge logs |

## Variables

### Core Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `project_name` | string | Project name | (required) |
| `environment` | string | Environment name | `dev` |
| `aws_region` | string | AWS region | `ap-northeast-1` |

### S3 Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `enable_s3_versioning` | bool | Enable versioning | `true` |
| `s3_lifecycle_rules` | list(object) | Lifecycle rules | `[]` |

### Cognito Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `cognito_domain_prefix` | string | Hosted UI domain prefix | (required) |
| `mfa_configuration` | string | MFA setting (OFF/ON/OPTIONAL) | `OFF` |
| `password_policy` | object | Password requirements | (see variables.tf) |
| `cognito_callback_urls` | list(string) | OAuth callback URLs | `["https://localhost/auth/callback"]` |
| `cognito_logout_urls` | list(string) | Logout URLs | `["https://localhost/"]` |
| `access_token_validity_hours` | number | Access token TTL (hours) | `1` |
| `id_token_validity_hours` | number | ID token TTL (hours) | `1` |
| `refresh_token_validity_days` | number | Refresh token TTL (days) | `30` |

### CloudFront Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `default_root_object` | string | Default index file | `index.html` |
| `cloudfront_price_class` | string | Price class | `PriceClass_200` |
| `geo_restriction_type` | string | Geo restriction | `none` |
| `geo_restriction_locations` | list(string) | Country codes | `[]` |
| `acm_certificate_arn` | string | Custom domain cert | `null` |
| `domain_aliases` | list(string) | Custom domain names | `[]` |

### Logging Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `log_retention_days` | number | Log retention days | `30` |

## Lambda Functions

Located in `lambda/` directory:

- `auth-check/` - Validates JWT tokens from cookies on viewer-request
- `auth-callback/` - Handles OAuth callback, exchanges code for tokens
- `auth-refresh/` - Refreshes expired tokens using refresh token

Build all functions with:
```bash
./build-lambdas.sh
```

## Deployment

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars (set project_name, cognito_domain_prefix)

# 2. Build Lambda functions
chmod +x build-lambdas.sh
./build-lambdas.sh

# 3. Initial deploy
terraform init
terraform plan
terraform apply

# 4. Update Cognito callback URLs with CloudFront domain
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
# Update terraform.tfvars:
# cognito_callback_urls = ["https://${CLOUDFRONT_DOMAIN}/auth/callback"]
# cognito_logout_urls   = ["https://${CLOUDFRONT_DOMAIN}/"]
terraform apply

# 5. Rebuild Lambdas with configuration values
REGION=$(terraform output -json lambda_config_values | jq -r '.COGNITO_REGION')
POOL_ID=$(terraform output -json lambda_config_values | jq -r '.COGNITO_USER_POOL_ID')
CLIENT_ID=$(terraform output -json lambda_config_values | jq -r '.COGNITO_CLIENT_ID')
CLIENT_SECRET=$(terraform output -raw cognito_client_secret)
COGNITO_DOMAIN=$(terraform output -json lambda_config_values | jq -r '.COGNITO_DOMAIN')
CF_DOMAIN=$(terraform output -json lambda_config_values | jq -r '.CLOUDFRONT_DOMAIN')

./build-lambdas.sh "$REGION" "$POOL_ID" "$CLIENT_ID" "$CLIENT_SECRET" "$COGNITO_DOMAIN" "$CF_DOMAIN"
terraform apply
```

## Testing

```bash
# Create test user
POOL_ID=$(terraform output -raw cognito_user_pool_id)
aws cognito-idp admin-create-user \
  --user-pool-id $POOL_ID \
  --username your@email.com \
  --user-attributes Name=email,Value=your@email.com Name=email_verified,Value=true \
  --temporary-password "TempPass123!"

# Upload test content
BUCKET=$(terraform output -raw content_bucket_name)
aws s3 cp test.jpg s3://$BUCKET/

# Access via browser
# https://<cloudfront-domain>/test.jpg
```

## Important Notes

- Lambda@Edge functions MUST be deployed to `us-east-1` (handled automatically)
- Deployment requires two passes: initial deploy, then update with CloudFront domain
- Lambda@Edge replica deletion can take up to 1 hour during destroy
- S3 bucket is completely private; access only via CloudFront with OAC
- JWT tokens are validated using Cognito JWKS
- Cookies are set with HttpOnly, Secure, and SameSite attributes
- CSRF protection via state parameter in OAuth flow
- CloudFront caching is disabled (TTL=0) for authenticated content
- For custom domains, provide `acm_certificate_arn` (must be in us-east-1) and `domain_aliases`
