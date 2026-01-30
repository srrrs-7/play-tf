#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/cloudfront-helpers.sh"

# CloudFront + Cognito + Lambda@Edge + S3 Architecture Script
# Provides Cognito-based authentication for S3 content via CloudFront

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront + Cognito + Lambda@Edge + S3 Authentication Architecture"
    echo ""
    echo "Full Stack Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status                               - Show status of all components"
    echo "  test-auth <cloudfront-url>           - Test authentication flow"
    echo ""
    echo "Cognito Commands:"
    echo "  cognito-create <name>                - Create Cognito User Pool"
    echo "  cognito-delete <pool-id>             - Delete Cognito User Pool"
    echo "  cognito-list                         - List Cognito User Pools"
    echo "  cognito-create-user <pool-id> <email> - Create test user"
    echo "  cognito-domain <pool-id> <prefix>    - Configure Cognito domain"
    echo ""
    echo "Lambda@Edge Commands:"
    echo "  edge-build                           - Build all Lambda@Edge functions"
    echo "  edge-deploy <stack-name>             - Deploy Lambda@Edge functions"
    echo "  edge-update <stack-name>             - Update Lambda@Edge functions"
    echo ""
    echo "S3 Commands:"
    echo "  s3-create <bucket-name>              - Create S3 bucket"
    echo "  s3-upload <bucket> <file>            - Upload file to S3"
    echo "  s3-sync <bucket> <local-dir>         - Sync local directory to S3"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <bucket> <stack-name>      - Create CloudFront distribution"
    echo "  cf-invalidate <dist-id>              - Invalidate CloudFront cache"
    echo ""
    exit 1
}

# ============================================
# Configuration Management
# ============================================

get_config_file() {
    local stack_name=$1
    echo "/tmp/${stack_name}-cognito-config.json"
}

save_config() {
    local stack_name=$1
    local config=$2
    echo "$config" > "$(get_config_file "$stack_name")"
}

load_config() {
    local stack_name=$1
    local config_file
    config_file=$(get_config_file "$stack_name")
    if [ -f "$config_file" ]; then
        cat "$config_file"
    else
        echo "{}"
    fi
}

# ============================================
# Cognito Functions
# ============================================

cognito_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "User pool name is required"
        exit 1
    fi

    log_step "Creating Cognito User Pool: $name"

    local pool_id
    pool_id=$(aws cognito-idp create-user-pool \
        --pool-name "$name" \
        --auto-verified-attributes email \
        --username-attributes email \
        --mfa-configuration OFF \
        --account-recovery-setting "RecoveryMechanisms=[{Priority=1,Name=verified_email}]" \
        --admin-create-user-config "AllowAdminCreateUserOnly=false" \
        --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}" \
        --query 'UserPool.Id' --output text)

    log_success "User Pool created: $pool_id"
    echo "$pool_id"
}

cognito_create_client() {
    local pool_id=$1
    local client_name=$2
    local callback_url=$3
    local logout_url=$4

    if [ -z "$pool_id" ] || [ -z "$client_name" ]; then
        log_error "Pool ID and client name are required"
        exit 1
    fi

    log_step "Creating Cognito App Client: $client_name"

    # Default URLs for initial creation (updated later with CloudFront domain)
    callback_url=${callback_url:-"https://localhost/auth/callback"}
    logout_url=${logout_url:-"https://localhost/"}

    local result
    result=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "$pool_id" \
        --client-name "$client_name" \
        --generate-secret \
        --explicit-auth-flows ALLOW_REFRESH_TOKEN_AUTH ALLOW_USER_SRP_AUTH \
        --supported-identity-providers COGNITO \
        --allowed-o-auth-flows code \
        --allowed-o-auth-scopes openid email profile \
        --allowed-o-auth-flows-user-pool-client \
        --callback-urls "$callback_url" \
        --logout-urls "$logout_url" \
        --prevent-user-existence-errors ENABLED \
        --output json)

    local client_id
    local client_secret
    client_id=$(echo "$result" | jq -r '.UserPoolClient.ClientId')
    client_secret=$(echo "$result" | jq -r '.UserPoolClient.ClientSecret')

    log_success "App Client created: $client_id"
    echo "$client_id $client_secret"
}

cognito_update_client_urls() {
    local pool_id=$1
    local client_id=$2
    local callback_url=$3
    local logout_url=$4

    log_step "Updating Cognito App Client URLs"

    aws cognito-idp update-user-pool-client \
        --user-pool-id "$pool_id" \
        --client-id "$client_id" \
        --callback-urls "$callback_url" \
        --logout-urls "$logout_url" \
        --allowed-o-auth-flows code \
        --allowed-o-auth-scopes openid email profile \
        --supported-identity-providers COGNITO \
        --allowed-o-auth-flows-user-pool-client > /dev/null

    log_success "App Client URLs updated"
}

cognito_domain() {
    local pool_id=$1
    local domain_prefix=$2

    if [ -z "$pool_id" ] || [ -z "$domain_prefix" ]; then
        log_error "Pool ID and domain prefix are required"
        exit 1
    fi

    log_step "Configuring Cognito domain: $domain_prefix"

    aws cognito-idp create-user-pool-domain \
        --user-pool-id "$pool_id" \
        --domain "$domain_prefix"

    local region
    region=$(get_region)
    local domain="${domain_prefix}.auth.${region}.amazoncognito.com"

    log_success "Cognito domain configured: $domain"
    echo "$domain"
}

cognito_delete() {
    local pool_id=$1

    if [ -z "$pool_id" ]; then
        log_error "Pool ID is required"
        exit 1
    fi

    confirm_action "This will delete Cognito User Pool: $pool_id"

    log_step "Deleting Cognito domain..."
    # Get and delete domain if exists
    local domain
    domain=$(aws cognito-idp describe-user-pool --user-pool-id "$pool_id" \
        --query 'UserPool.Domain' --output text 2>/dev/null || true)

    if [ -n "$domain" ] && [ "$domain" != "None" ]; then
        aws cognito-idp delete-user-pool-domain \
            --user-pool-id "$pool_id" \
            --domain "$domain" 2>/dev/null || true
    fi

    log_step "Deleting Cognito User Pool..."
    aws cognito-idp delete-user-pool --user-pool-id "$pool_id"

    log_success "User Pool deleted: $pool_id"
}

cognito_list() {
    log_info "Listing Cognito User Pools..."
    aws cognito-idp list-user-pools --max-results 60 \
        --query 'UserPools[].{Id:Id,Name:Name,CreationDate:CreationDate}' \
        --output table
}

cognito_create_user() {
    local pool_id=$1
    local email=$2

    if [ -z "$pool_id" ] || [ -z "$email" ]; then
        log_error "Pool ID and email are required"
        exit 1
    fi

    log_step "Creating test user: $email"

    # Create user with temporary password
    local temp_password="TempPass123!"

    aws cognito-idp admin-create-user \
        --user-pool-id "$pool_id" \
        --username "$email" \
        --user-attributes Name=email,Value="$email" Name=email_verified,Value=true \
        --temporary-password "$temp_password" \
        --message-action SUPPRESS > /dev/null

    # Set permanent password
    aws cognito-idp admin-set-user-password \
        --user-pool-id "$pool_id" \
        --username "$email" \
        --password "$temp_password" \
        --permanent > /dev/null

    log_success "User created: $email"
    echo "Temporary password: $temp_password"
    echo "User should change password on first login"
}

# ============================================
# Lambda@Edge Functions
# ============================================

edge_build() {
    log_step "Building Lambda@Edge functions..."

    local lambda_dir="$SCRIPT_DIR/lambda"

    for func_dir in auth-check auth-callback auth-refresh; do
        log_info "Building $func_dir..."
        cd "$lambda_dir/$func_dir"
        ./build.sh
        cd "$SCRIPT_DIR"
    done

    log_success "All Lambda@Edge functions built"
}

inject_config() {
    local file=$1
    local region=$2
    local pool_id=$3
    local client_id=$4
    local client_secret=$5
    local cognito_domain=$6
    local cloudfront_domain=$7

    sed -i "s|{{COGNITO_REGION}}|$region|g" "$file"
    sed -i "s|{{COGNITO_USER_POOL_ID}}|$pool_id|g" "$file"
    sed -i "s|{{COGNITO_CLIENT_ID}}|$client_id|g" "$file"
    sed -i "s|{{COGNITO_CLIENT_SECRET}}|$client_secret|g" "$file"
    sed -i "s|{{COGNITO_DOMAIN}}|$cognito_domain|g" "$file"
    sed -i "s|{{CLOUDFRONT_DOMAIN}}|$cloudfront_domain|g" "$file"
}

edge_deploy() {
    local stack_name=$1
    local region=$2
    local pool_id=$3
    local client_id=$4
    local client_secret=$5
    local cognito_domain=$6
    local cloudfront_domain=$7

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_step "Deploying Lambda@Edge functions (us-east-1)"

    local account_id
    account_id=$(get_account_id)

    # Create IAM role for Lambda@Edge
    local role_name="${stack_name}-edge-role"
    local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "lambda.amazonaws.com",
                    "edgelambda.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)

    log_info "Creating IAM role: $role_name"
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    log_info "Waiting for IAM role propagation..."
    sleep 15

    local role_arn="arn:aws:iam::$account_id:role/$role_name"
    local lambda_dir="$SCRIPT_DIR/lambda"
    local temp_dir="/tmp/${stack_name}-lambda-build"

    mkdir -p "$temp_dir"

    local function_arns=""

    for func_name in auth-check auth-callback auth-refresh; do
        log_info "Deploying $func_name..."

        # Copy and inject config
        local src_dir="$lambda_dir/$func_name"
        local build_dir="$temp_dir/$func_name"

        rm -rf "$build_dir"
        cp -r "$src_dir" "$build_dir"

        # Build (use bun if available, fallback to npm)
        cd "$build_dir"
        rm -rf dist node_modules
        if command -v bun &> /dev/null; then
            bun install
            bun run build
        else
            npm install
            npm run build
        fi

        # Inject configuration into compiled files
        for js_file in dist/*.js; do
            inject_config "$js_file" "$region" "$pool_id" "$client_id" "$client_secret" "$cognito_domain" "$cloudfront_domain"
        done

        # Create zip
        cd dist
        zip -r ../function.zip .
        cd ..

        local full_name="${stack_name}-${func_name}"

        # Delete existing function if exists
        aws lambda delete-function --function-name "$full_name" --region us-east-1 2>/dev/null || true

        # Create function
        aws lambda create-function \
            --function-name "$full_name" \
            --runtime nodejs18.x \
            --handler index.handler \
            --role "$role_arn" \
            --zip-file "fileb://function.zip" \
            --timeout 5 \
            --memory-size 128 \
            --region us-east-1 > /dev/null

        # Wait for function to be active
        aws lambda wait function-active --function-name "$full_name" --region us-east-1

        # Publish version
        local version
        version=$(aws lambda publish-version \
            --function-name "$full_name" \
            --region us-east-1 \
            --query 'Version' --output text)

        local func_arn="arn:aws:lambda:us-east-1:$account_id:function:$full_name:$version"
        function_arns="$function_arns $func_name=$func_arn"

        log_info "Deployed $func_name version $version"

        cd "$SCRIPT_DIR"
    done

    rm -rf "$temp_dir"

    log_success "All Lambda@Edge functions deployed"
    echo "$function_arns"
}

edge_update() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    local config
    config=$(load_config "$stack_name")

    if [ "$config" = "{}" ]; then
        log_error "No configuration found for stack: $stack_name"
        exit 1
    fi

    local region pool_id client_id client_secret cognito_domain cloudfront_domain
    region=$(echo "$config" | jq -r '.region')
    pool_id=$(echo "$config" | jq -r '.pool_id')
    client_id=$(echo "$config" | jq -r '.client_id')
    client_secret=$(echo "$config" | jq -r '.client_secret')
    cognito_domain=$(echo "$config" | jq -r '.cognito_domain')
    cloudfront_domain=$(echo "$config" | jq -r '.cloudfront_domain')

    edge_deploy "$stack_name" "$region" "$pool_id" "$client_id" "$client_secret" "$cognito_domain" "$cloudfront_domain"
}

# ============================================
# S3 Functions
# ============================================

s3_create() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_step "Creating S3 bucket: $bucket"

    local region
    region=$(get_region)

    if [ "$region" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket"
    else
        aws s3api create-bucket --bucket "$bucket" \
            --create-bucket-configuration LocationConstraint="$region"
    fi

    # Block public access
    aws s3api put-public-access-block \
        --bucket "$bucket" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "$bucket" \
        --server-side-encryption-configuration \
            '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

    log_success "S3 bucket created: $bucket"
}

s3_upload() {
    local bucket=$1
    local file=$2

    if [ -z "$bucket" ] || [ -z "$file" ]; then
        log_error "Bucket and file are required"
        exit 1
    fi

    require_file "$file" "Source file"

    aws s3 cp "$file" "s3://$bucket/"
    log_success "File uploaded to s3://$bucket/"
}

s3_sync() {
    local bucket=$1
    local local_dir=$2

    if [ -z "$bucket" ] || [ -z "$local_dir" ]; then
        log_error "Bucket and local directory are required"
        exit 1
    fi

    require_directory "$local_dir" "Source directory"

    aws s3 sync "$local_dir" "s3://$bucket/" --delete
    log_success "Sync completed"
}

# ============================================
# CloudFront Functions
# ============================================

cf_create_with_cognito() {
    local bucket=$1
    local stack_name=$2
    local auth_check_arn=$3
    local auth_callback_arn=$4
    local auth_refresh_arn=$5

    if [ -z "$bucket" ] || [ -z "$stack_name" ]; then
        log_error "Bucket name and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution with Cognito authentication"

    local region
    region=$(get_region)

    # Create Origin Access Control
    local oac_name="${stack_name}-oac"
    local oac_id
    oac_id=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config "{
            \"Name\": \"$oac_name\",
            \"SigningProtocol\": \"sigv4\",
            \"SigningBehavior\": \"always\",
            \"OriginAccessControlOriginType\": \"s3\"
        }" \
        --query 'OriginAccessControl.Id' --output text)

    log_info "Origin Access Control created: $oac_id"

    # Create distribution config
    local dist_config
    dist_config=$(jq -n \
        --arg caller_ref "$stack_name-$(date +%s)" \
        --arg comment "CloudFront with Cognito Auth for $stack_name" \
        --arg bucket "$bucket" \
        --arg region "$region" \
        --arg oac_id "$oac_id" \
        --arg auth_check_arn "$auth_check_arn" \
        --arg auth_callback_arn "$auth_callback_arn" \
        --arg auth_refresh_arn "$auth_refresh_arn" \
        '{
            "CallerReference": $caller_ref,
            "Comment": $comment,
            "DefaultCacheBehavior": {
                "TargetOriginId": ("S3-" + $bucket),
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
                    "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
                },
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "Compress": true,
                "LambdaFunctionAssociations": {
                    "Quantity": 1,
                    "Items": [{
                        "LambdaFunctionARN": $auth_check_arn,
                        "EventType": "viewer-request",
                        "IncludeBody": false
                    }]
                }
            },
            "CacheBehaviors": {
                "Quantity": 2,
                "Items": [
                    {
                        "PathPattern": "/auth/callback",
                        "TargetOriginId": ("S3-" + $bucket),
                        "ViewerProtocolPolicy": "redirect-to-https",
                        "AllowedMethods": {
                            "Quantity": 2,
                            "Items": ["GET", "HEAD"],
                            "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
                        },
                        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                        "Compress": false,
                        "LambdaFunctionAssociations": {
                            "Quantity": 1,
                            "Items": [{
                                "LambdaFunctionARN": $auth_callback_arn,
                                "EventType": "viewer-request",
                                "IncludeBody": false
                            }]
                        }
                    },
                    {
                        "PathPattern": "/auth/refresh",
                        "TargetOriginId": ("S3-" + $bucket),
                        "ViewerProtocolPolicy": "redirect-to-https",
                        "AllowedMethods": {
                            "Quantity": 2,
                            "Items": ["GET", "HEAD"],
                            "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
                        },
                        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                        "Compress": false,
                        "LambdaFunctionAssociations": {
                            "Quantity": 1,
                            "Items": [{
                                "LambdaFunctionARN": $auth_refresh_arn,
                                "EventType": "viewer-request",
                                "IncludeBody": false
                            }]
                        }
                    }
                ]
            },
            "Origins": {
                "Quantity": 1,
                "Items": [{
                    "Id": ("S3-" + $bucket),
                    "DomainName": ($bucket + ".s3." + $region + ".amazonaws.com"),
                    "OriginAccessControlId": $oac_id,
                    "S3OriginConfig": {"OriginAccessIdentity": ""}
                }]
            },
            "Enabled": true,
            "PriceClass": "PriceClass_200",
            "ViewerCertificate": {
                "CloudFrontDefaultCertificate": true,
                "MinimumProtocolVersion": "TLSv1.2_2021"
            }
        }')

    local result
    result=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --output json)

    local dist_id domain_name
    dist_id=$(echo "$result" | jq -r '.Distribution.Id')
    domain_name=$(echo "$result" | jq -r '.Distribution.DomainName')

    # Set S3 bucket policy for OAC
    local account_id
    account_id=$(get_account_id)

    local bucket_policy
    bucket_policy=$(jq -n \
        --arg bucket "$bucket" \
        --arg dist_arn "arn:aws:cloudfront::$account_id:distribution/$dist_id" \
        '{
            "Version": "2012-10-17",
            "Statement": [{
                "Sid": "AllowCloudFrontServicePrincipal",
                "Effect": "Allow",
                "Principal": {"Service": "cloudfront.amazonaws.com"},
                "Action": "s3:GetObject",
                "Resource": ("arn:aws:s3:::" + $bucket + "/*"),
                "Condition": {
                    "StringEquals": {
                        "AWS:SourceArn": $dist_arn
                    }
                }
            }]
        }')

    aws s3api put-bucket-policy --bucket "$bucket" --policy "$bucket_policy"

    log_success "CloudFront distribution created"
    echo "$dist_id $domain_name $oac_id"
}

cf_invalidate() {
    local dist_id=$1
    local path=${2:-"/*"}

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    aws cloudfront create-invalidation --distribution-id "$dist_id" --paths "$path" > /dev/null
    log_success "Invalidation created for: $path"
}

# ============================================
# Full Stack Operations
# ============================================

deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_info "Deploying CloudFront + Cognito + Lambda@Edge + S3: $stack_name"
    echo ""
    echo "This will create:"
    echo "  - Cognito User Pool with Hosted UI"
    echo "  - S3 bucket (private)"
    echo "  - Lambda@Edge functions (3)"
    echo "  - CloudFront distribution with authentication"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 0
    fi

    local region
    region=$(get_region)
    local bucket="${stack_name}-content-$(date +%Y%m%d)"

    # Step 1: Create Cognito User Pool
    log_step "Step 1/8: Creating Cognito User Pool..."
    local pool_id
    pool_id=$(cognito_create "$stack_name")

    # Step 2: Create App Client
    log_step "Step 2/8: Creating Cognito App Client..."
    local client_result client_id client_secret
    client_result=$(cognito_create_client "$pool_id" "${stack_name}-client")
    client_id=$(echo "$client_result" | cut -d' ' -f1)
    client_secret=$(echo "$client_result" | cut -d' ' -f2)

    # Step 3: Configure Cognito domain
    log_step "Step 3/8: Configuring Cognito domain..."
    local domain_prefix="${stack_name}-$(date +%s)"
    local cognito_domain
    cognito_domain=$(cognito_domain "$pool_id" "$domain_prefix")

    # Step 4: Create S3 bucket
    log_step "Step 4/8: Creating S3 bucket..."
    s3_create "$bucket"

    # Step 5: Build Lambda@Edge functions
    log_step "Step 5/8: Building Lambda@Edge functions..."
    edge_build

    # Step 6: Deploy Lambda@Edge with temporary CloudFront domain
    log_step "Step 6/8: Deploying Lambda@Edge functions..."
    # Use placeholder for initial deployment
    local temp_cf_domain="temp.cloudfront.net"
    local arns_output
    arns_output=$(edge_deploy "$stack_name" "$region" "$pool_id" "$client_id" "$client_secret" "$cognito_domain" "$temp_cf_domain")

    # Parse ARNs
    local auth_check_arn auth_callback_arn auth_refresh_arn
    for item in $arns_output; do
        case "$item" in
            auth-check=*) auth_check_arn="${item#auth-check=}" ;;
            auth-callback=*) auth_callback_arn="${item#auth-callback=}" ;;
            auth-refresh=*) auth_refresh_arn="${item#auth-refresh=}" ;;
        esac
    done

    # Step 7: Create CloudFront distribution
    log_step "Step 7/8: Creating CloudFront distribution..."
    local cf_result dist_id cloudfront_domain oac_id
    cf_result=$(cf_create_with_cognito "$bucket" "$stack_name" "$auth_check_arn" "$auth_callback_arn" "$auth_refresh_arn")
    dist_id=$(echo "$cf_result" | cut -d' ' -f1)
    cloudfront_domain=$(echo "$cf_result" | cut -d' ' -f2)
    oac_id=$(echo "$cf_result" | cut -d' ' -f3)

    # Step 8: Update Lambda@Edge with actual CloudFront domain and update Cognito URLs
    log_step "Step 8/8: Finalizing configuration..."

    # Re-deploy Lambda@Edge with actual CloudFront domain
    arns_output=$(edge_deploy "$stack_name" "$region" "$pool_id" "$client_id" "$client_secret" "$cognito_domain" "$cloudfront_domain")

    # Parse new ARNs
    for item in $arns_output; do
        case "$item" in
            auth-check=*) auth_check_arn="${item#auth-check=}" ;;
            auth-callback=*) auth_callback_arn="${item#auth-callback=}" ;;
            auth-refresh=*) auth_refresh_arn="${item#auth-refresh=}" ;;
        esac
    done

    # Update Cognito App Client with CloudFront URLs
    cognito_update_client_urls "$pool_id" "$client_id" \
        "https://${cloudfront_domain}/auth/callback" \
        "https://${cloudfront_domain}/"

    # Update CloudFront distribution with new Lambda@Edge versions
    log_info "Updating CloudFront with final Lambda@Edge versions..."

    local etag config
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig')

    # Update Lambda associations
    config=$(echo "$config" | jq \
        --arg auth_check_arn "$auth_check_arn" \
        --arg auth_callback_arn "$auth_callback_arn" \
        --arg auth_refresh_arn "$auth_refresh_arn" '
        .DefaultCacheBehavior.LambdaFunctionAssociations.Items[0].LambdaFunctionARN = $auth_check_arn |
        .CacheBehaviors.Items[0].LambdaFunctionAssociations.Items[0].LambdaFunctionARN = $auth_callback_arn |
        .CacheBehaviors.Items[1].LambdaFunctionAssociations.Items[0].LambdaFunctionARN = $auth_refresh_arn
    ')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$config" > /dev/null

    # Save configuration
    local config_data
    config_data=$(jq -n \
        --arg stack_name "$stack_name" \
        --arg region "$region" \
        --arg bucket "$bucket" \
        --arg pool_id "$pool_id" \
        --arg client_id "$client_id" \
        --arg client_secret "$client_secret" \
        --arg cognito_domain "$cognito_domain" \
        --arg cloudfront_domain "$cloudfront_domain" \
        --arg dist_id "$dist_id" \
        --arg oac_id "$oac_id" \
        '{
            stack_name: $stack_name,
            region: $region,
            bucket: $bucket,
            pool_id: $pool_id,
            client_id: $client_id,
            client_secret: $client_secret,
            cognito_domain: $cognito_domain,
            cloudfront_domain: $cloudfront_domain,
            dist_id: $dist_id,
            oac_id: $oac_id
        }')
    save_config "$stack_name" "$config_data"

    # Wait for deployment
    log_info "Waiting for CloudFront deployment (this may take several minutes)..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "CloudFront URL: https://${cloudfront_domain}"
    echo "Cognito User Pool ID: $pool_id"
    echo "Cognito Domain: https://${cognito_domain}"
    echo "S3 Bucket: $bucket"
    echo "Distribution ID: $dist_id"
    echo ""
    echo "Next Steps:"
    echo "  1. Create a test user:"
    echo "     $0 cognito-create-user $pool_id your@email.com"
    echo ""
    echo "  2. Upload test content:"
    echo "     $0 s3-upload $bucket test.jpg"
    echo ""
    echo "  3. Test authentication:"
    echo "     Open https://${cloudfront_domain}/test.jpg in browser"
    echo ""
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    local config
    config=$(load_config "$stack_name")

    if [ "$config" = "{}" ]; then
        log_error "No configuration found for stack: $stack_name"
        log_info "Try providing the resource IDs manually"
        exit 1
    fi

    local bucket pool_id dist_id oac_id
    bucket=$(echo "$config" | jq -r '.bucket')
    pool_id=$(echo "$config" | jq -r '.pool_id')
    dist_id=$(echo "$config" | jq -r '.dist_id')
    oac_id=$(echo "$config" | jq -r '.oac_id')

    confirm_action "This will destroy all resources for stack: $stack_name"

    # Step 1: Disable and delete CloudFront
    log_step "Step 1/6: Disabling CloudFront distribution..."
    local etag config_data
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    config_data=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig')

    # Remove Lambda associations first
    config_data=$(echo "$config_data" | jq '
        .DefaultCacheBehavior.LambdaFunctionAssociations = {"Quantity": 0, "Items": []} |
        .CacheBehaviors.Items[].LambdaFunctionAssociations = {"Quantity": 0, "Items": []} |
        .Enabled = false
    ')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$config_data" > /dev/null

    log_info "Waiting for CloudFront to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    log_step "Step 2/6: Deleting CloudFront distribution..."
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"

    # Delete OAC
    log_step "Step 3/6: Deleting Origin Access Control..."
    local oac_etag
    oac_etag=$(aws cloudfront get-origin-access-control --id "$oac_id" --query 'ETag' --output text 2>/dev/null || echo "")
    if [ -n "$oac_etag" ]; then
        aws cloudfront delete-origin-access-control --id "$oac_id" --if-match "$oac_etag" 2>/dev/null || true
    fi

    # Delete Lambda@Edge (need to wait for replicas)
    log_step "Step 4/6: Deleting Lambda@Edge functions..."
    log_warn "Lambda@Edge replicas may take up to an hour to be deleted."
    log_info "Attempting to delete Lambda functions..."

    local account_id
    account_id=$(get_account_id)
    local role_name="${stack_name}-edge-role"

    for func_name in auth-check auth-callback auth-refresh; do
        local full_name="${stack_name}-${func_name}"
        log_info "Deleting $full_name..."

        # Delete all versions
        local versions
        versions=$(aws lambda list-versions-by-function \
            --function-name "$full_name" \
            --region us-east-1 \
            --query 'Versions[?Version!=`$LATEST`].Version' --output text 2>/dev/null || true)

        for version in $versions; do
            aws lambda delete-function --function-name "$full_name" --qualifier "$version" --region us-east-1 2>/dev/null || true
        done

        # Delete function
        aws lambda delete-function --function-name "$full_name" --region us-east-1 2>/dev/null || true
    done

    # Delete IAM role
    log_info "Deleting IAM role..."
    delete_role_with_policies "$role_name"

    # Delete S3 bucket
    log_step "Step 5/6: Deleting S3 bucket..."
    aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
    aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true

    # Delete Cognito
    log_step "Step 6/6: Deleting Cognito User Pool..."
    local cognito_domain
    cognito_domain=$(aws cognito-idp describe-user-pool --user-pool-id "$pool_id" \
        --query 'UserPool.Domain' --output text 2>/dev/null || true)

    if [ -n "$cognito_domain" ] && [ "$cognito_domain" != "None" ]; then
        aws cognito-idp delete-user-pool-domain \
            --user-pool-id "$pool_id" \
            --domain "$cognito_domain" 2>/dev/null || true
    fi

    aws cognito-idp delete-user-pool --user-pool-id "$pool_id" 2>/dev/null || true

    # Delete CloudWatch log groups
    log_info "Deleting CloudWatch log groups..."
    for func_name in auth-check auth-callback auth-refresh; do
        local log_group="/aws/lambda/us-east-1.${stack_name}-${func_name}"
        aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
    done

    # Remove config file
    rm -f "$(get_config_file "$stack_name")"

    log_success "Stack destroyed: $stack_name"
}

status() {
    echo -e "${BLUE}=== Cognito User Pools ===${NC}"
    cognito_list

    echo -e "\n${BLUE}=== Lambda@Edge Functions (us-east-1) ===${NC}"
    aws lambda list-functions \
        --region us-east-1 \
        --query 'Functions[?contains(FunctionName, `-auth-`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
        --output table

    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Enabled:Enabled}' \
        --output table
}

test_auth() {
    local cloudfront_url=$1

    if [ -z "$cloudfront_url" ]; then
        log_error "CloudFront URL is required"
        exit 1
    fi

    # Remove trailing slash
    cloudfront_url="${cloudfront_url%/}"

    log_step "Testing authentication flow for: $cloudfront_url"

    echo ""
    echo "Test 1: Unauthenticated request (should redirect to Cognito)"
    local response
    response=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" "$cloudfront_url/test.jpg" 2>/dev/null || echo "000")
    local status_code redirect_url
    status_code=$(echo "$response" | cut -d' ' -f1)
    redirect_url=$(echo "$response" | cut -d' ' -f2)

    if [ "$status_code" = "302" ] && echo "$redirect_url" | grep -q "amazoncognito.com"; then
        echo -e "  ${GREEN}PASS${NC}: Got 302 redirect to Cognito"
    else
        echo -e "  ${RED}FAIL${NC}: Expected 302 redirect to Cognito, got: $status_code"
    fi

    echo ""
    echo "Test 2: Callback endpoint exists"
    response=$(curl -s -o /dev/null -w "%{http_code}" "$cloudfront_url/auth/callback" 2>/dev/null || echo "000")
    if [ "$response" = "400" ] || [ "$response" = "302" ]; then
        echo -e "  ${GREEN}PASS${NC}: Callback endpoint responds (status: $response)"
    else
        echo -e "  ${YELLOW}WARN${NC}: Callback endpoint returned: $response"
    fi

    echo ""
    echo "Test 3: Logout endpoint"
    response=$(curl -s -o /dev/null -w "%{http_code}" "$cloudfront_url/auth/logout" 2>/dev/null || echo "000")
    if [ "$response" = "302" ]; then
        echo -e "  ${GREEN}PASS${NC}: Logout endpoint redirects"
    else
        echo -e "  ${YELLOW}WARN${NC}: Logout endpoint returned: $response"
    fi

    echo ""
    log_info "Manual testing:"
    echo "  1. Open browser: $cloudfront_url/test.jpg"
    echo "  2. Should redirect to Cognito login"
    echo "  3. Login with test user"
    echo "  4. Should redirect back and display content"
}

# ============================================
# Main
# ============================================

check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status "$@" ;;
    test-auth) test_auth "$@" ;;
    cognito-create) cognito_create "$@" ;;
    cognito-delete) cognito_delete "$@" ;;
    cognito-list) cognito_list ;;
    cognito-create-user) cognito_create_user "$@" ;;
    cognito-domain) cognito_domain "$@" ;;
    edge-build) edge_build ;;
    edge-deploy) edge_deploy "$@" ;;
    edge-update) edge_update "$@" ;;
    s3-create) s3_create "$@" ;;
    s3-upload) s3_upload "$@" ;;
    s3-sync) s3_sync "$@" ;;
    cf-create) cf_create_with_cognito "$@" ;;
    cf-invalidate) cf_invalidate "$@" ;;
    *) log_error "Unknown command: $COMMAND"; usage ;;
esac
