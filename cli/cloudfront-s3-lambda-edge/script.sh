#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# CloudFront → S3 → Lambda@Edge Architecture Script
# Provides operations for edge computing with static hosting

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → S3 → Lambda@Edge Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status                               - Show status of all components"
    echo ""
    echo "Lambda@Edge Commands:"
    echo "  edge-create <name> <type> <zip-file> - Create Lambda@Edge function"
    echo "  edge-delete <name>                   - Delete Lambda@Edge function"
    echo "  edge-list                            - List Lambda functions in us-east-1"
    echo "  edge-publish <name>                  - Publish new version"
    echo "  edge-associate <dist-id> <func-arn> <event-type> - Associate with CloudFront"
    echo "  edge-disassociate <dist-id> <event-type> - Remove Lambda@Edge association"
    echo ""
    echo "Lambda@Edge Event Types:"
    echo "  viewer-request   - Runs after CloudFront receives request from viewer"
    echo "  viewer-response  - Runs before CloudFront returns response to viewer"
    echo "  origin-request   - Runs before CloudFront forwards request to origin"
    echo "  origin-response  - Runs after CloudFront receives response from origin"
    echo ""
    echo "S3 Commands:"
    echo "  s3-create <bucket-name>              - Create S3 bucket"
    echo "  s3-delete <bucket-name>              - Delete S3 bucket"
    echo "  s3-sync <local-dir> <bucket>         - Sync local directory to S3"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <bucket> <stack-name>      - Create CloudFront distribution"
    echo "  cf-delete <dist-id>                  - Delete CloudFront distribution"
    echo "  cf-list                              - List CloudFront distributions"
    echo "  cf-invalidate <dist-id> [path]       - Invalidate cache"
    echo ""
    exit 1
}

# ============================================
# Lambda@Edge Functions (must be in us-east-1)
# ============================================

edge_create() {
    local name=$1
    local event_type=$2  # viewer-request, viewer-response, origin-request, origin-response
    local zip_file=$3

    if [ -z "$name" ] || [ -z "$event_type" ] || [ -z "$zip_file" ]; then
        log_error "Function name, event type, and zip file are required"
        exit 1
    fi

    log_step "Creating Lambda@Edge function in us-east-1: $name"

    # Lambda@Edge must be created in us-east-1
    local account_id
    account_id=$(get_account_id)

    # Create execution role
    local role_name="${name}-edge-role"
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

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    log_info "Waiting for role to propagate..."
    sleep 10

    local role_arn="arn:aws:iam::$account_id:role/$role_name"

    # Determine runtime and handler based on event type
    local timeout=5
    local memory=128

    if [ "$event_type" = "origin-request" ] || [ "$event_type" = "origin-response" ]; then
        timeout=30
    fi

    # Create function in us-east-1
    aws lambda create-function \
        --function-name "$name" \
        --runtime nodejs18.x \
        --handler index.handler \
        --role "$role_arn" \
        --zip-file "fileb://$zip_file" \
        --timeout "$timeout" \
        --memory-size "$memory" \
        --region us-east-1

    log_info "Lambda@Edge function created: $name"
    log_info "Run 'edge-publish $name' to create a version for CloudFront"
}

edge_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_warn "This will delete Lambda@Edge function: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting Lambda@Edge function"

    # Delete all versions except $LATEST
    local versions
    versions=$(aws lambda list-versions-by-function \
        --function-name "$name" \
        --region us-east-1 \
        --query 'Versions[?Version!=`$LATEST`].Version' --output text)

    for version in $versions; do
        log_info "Deleting version: $version"
        aws lambda delete-function --function-name "$name" --qualifier "$version" --region us-east-1 2>/dev/null || true
    done

    # Delete function
    aws lambda delete-function --function-name "$name" --region us-east-1

    log_info "Lambda@Edge function deleted"
}

edge_list() {
    log_info "Listing Lambda functions in us-east-1..."
    aws lambda list-functions \
        --region us-east-1 \
        --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize}' \
        --output table
}

edge_publish() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_step "Publishing new version for: $name"

    local version
    version=$(aws lambda publish-version \
        --function-name "$name" \
        --region us-east-1 \
        --query 'Version' --output text)

    local account_id
    account_id=$(get_account_id)
    local func_arn="arn:aws:lambda:us-east-1:$account_id:function:$name:$version"

    log_info "Published version: $version"
    echo "Function ARN: $func_arn"
    echo ""
    echo "Use this ARN with 'edge-associate' command"
}

edge_associate() {
    local dist_id=$1
    local func_arn=$2
    local event_type=$3  # viewer-request, viewer-response, origin-request, origin-response

    if [ -z "$dist_id" ] || [ -z "$func_arn" ] || [ -z "$event_type" ]; then
        log_error "Distribution ID, function ARN, and event type are required"
        exit 1
    fi

    log_step "Associating Lambda@Edge with CloudFront"

    # Get current config
    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig')

    # Convert event type to CloudFront format
    local cf_event_type
    case $event_type in
        viewer-request) cf_event_type="viewer-request" ;;
        viewer-response) cf_event_type="viewer-response" ;;
        origin-request) cf_event_type="origin-request" ;;
        origin-response) cf_event_type="origin-response" ;;
        *) log_error "Invalid event type: $event_type"; exit 1 ;;
    esac

    # Update config with Lambda association
    local updated_config
    updated_config=$(echo "$config" | jq --arg arn "$func_arn" --arg et "$cf_event_type" '
        .DefaultCacheBehavior.LambdaFunctionAssociations = {
            "Quantity": 1,
            "Items": [{
                "LambdaFunctionARN": $arn,
                "EventType": $et,
                "IncludeBody": false
            }]
        }
    ')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$updated_config"

    log_info "Lambda@Edge associated with CloudFront"
    log_info "Changes may take 5-10 minutes to propagate globally"
}

edge_disassociate() {
    local dist_id=$1
    local event_type=$2

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_step "Removing Lambda@Edge association"

    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig')

    # Remove Lambda associations
    local updated_config
    updated_config=$(echo "$config" | jq '.DefaultCacheBehavior.LambdaFunctionAssociations = {"Quantity": 0, "Items": []}')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$updated_config"

    log_info "Lambda@Edge association removed"
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

    if [ "$DEFAULT_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket"
    else
        aws s3api create-bucket --bucket "$bucket" \
            --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi

    aws s3api put-public-access-block \
        --bucket "$bucket" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    log_info "S3 bucket created"
}

s3_delete() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_warn "This will delete bucket: $bucket"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    aws s3 rb "s3://$bucket" --force
    log_info "Bucket deleted"
}

s3_sync() {
    local local_dir=$1
    local bucket=$2

    if [ -z "$local_dir" ] || [ -z "$bucket" ]; then
        log_error "Local directory and bucket are required"
        exit 1
    fi

    aws s3 sync "$local_dir" "s3://$bucket" --delete
    log_info "Sync completed"
}

# ============================================
# CloudFront Functions
# ============================================

cf_create() {
    local bucket=$1
    local stack_name=$2

    if [ -z "$bucket" ] || [ -z "$stack_name" ]; then
        log_error "Bucket name and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution with OAI"

    # Create OAI
    local oai_id
    oai_id=$(aws cloudfront create-cloud-front-origin-access-identity \
        --cloud-front-origin-access-identity-config "CallerReference=$(date +%s),Comment=OAI for $stack_name" \
        --query 'CloudFrontOriginAccessIdentity.Id' --output text)

    # Get the OAI's S3 Canonical User ID for the policy
    local oai_canonical
    oai_canonical=$(aws cloudfront get-cloud-front-origin-access-identity \
        --id "$oai_id" \
        --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' --output text)

    # Set bucket policy
    local policy
    policy=$(jq -n \
        --arg bucket "$bucket" \
        --arg oai_canonical "$oai_canonical" \
        '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"CanonicalUser": $oai_canonical},
                "Action": "s3:GetObject",
                "Resource": ("arn:aws:s3:::" + $bucket + "/*")
            }]
        }')
    aws s3api put-bucket-policy --bucket "$bucket" --policy "$policy"

    local dist_config
    dist_config=$(jq -n \
        --arg caller_ref "$stack_name-$(date +%s)" \
        --arg comment "CloudFront with Lambda@Edge for $stack_name" \
        --arg bucket "$bucket" \
        --arg region "$DEFAULT_REGION" \
        --arg oai_id "$oai_id" \
        '{
            "CallerReference": $caller_ref,
            "Comment": $comment,
            "DefaultCacheBehavior": {
                "TargetOriginId": ("S3-" + $bucket),
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                },
                "ForwardedValues": {"QueryString": false, "Cookies": {"Forward": "none"}},
                "MinTTL": 0,
                "DefaultTTL": 86400,
                "MaxTTL": 31536000,
                "Compress": true,
                "LambdaFunctionAssociations": {"Quantity": 0, "Items": []}
            },
            "Origins": {
                "Quantity": 1,
                "Items": [{
                    "Id": ("S3-" + $bucket),
                    "DomainName": ($bucket + ".s3." + $region + ".amazonaws.com"),
                    "S3OriginConfig": {"OriginAccessIdentity": ("origin-access-identity/cloudfront/" + $oai_id)}
                }]
            },
            "DefaultRootObject": "index.html",
            "ViewerCertificate": {
                "CloudFrontDefaultCertificate": true,
                "MinimumProtocolVersion": "TLSv1.2_2021",
                "SSLSupportMethod": "sni-only"
            },
            "Enabled": true,
            "PriceClass": "PriceClass_200"
        }')

    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --query 'Distribution.Id' --output text)

    local domain_name
    domain_name=$(aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DomainName' --output text)

    echo ""
    echo -e "${GREEN}CloudFront Distribution Created${NC}"
    echo "Distribution ID: $dist_id"
    echo "Domain Name: $domain_name"
    echo "OAI ID: $oai_id"
}

cf_delete() {
    local dist_id=$1

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_warn "This will delete distribution: $dist_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Disable first
    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)
    local disabled_config
    disabled_config=$(echo "$config" | jq '.Enabled = false')

    aws cloudfront update-distribution --id "$dist_id" --if-match "$etag" --distribution-config "$disabled_config"

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"

    log_info "Distribution deleted"
}

cf_list() {
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status}' \
        --output table
}

cf_invalidate() {
    local dist_id=$1
    local path=${2:-"/*"}

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    aws cloudfront create-invalidation --distribution-id "$dist_id" --paths "$path"
    log_info "Invalidation created"
}

# ============================================
# Full Stack
# ============================================

deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_info "Deploying CloudFront + S3 + Lambda@Edge: $stack_name"
    echo ""
    echo "This will create:"
    echo "  - S3 bucket"
    echo "  - CloudFront distribution"
    echo "  - Sample Lambda@Edge function"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 0
    fi

    local bucket="${stack_name}-static-$(date +%Y%m%d)"

    # Create S3
    log_step "Creating S3 bucket..."
    s3_create "$bucket"

    # Create CloudFront
    log_step "Creating CloudFront..."
    cf_create "$bucket" "$stack_name"

    # Create sample Lambda@Edge function
    log_step "Creating sample Lambda@Edge function..."

    local lambda_dir="/tmp/${stack_name}-edge"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
'use strict';

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;

    // Add security headers example
    const response = event.Records[0].cf.response || {
        status: '200',
        headers: {}
    };

    response.headers['x-frame-options'] = [{ value: 'DENY' }];
    response.headers['x-content-type-options'] = [{ value: 'nosniff' }];
    response.headers['x-xss-protection'] = [{ value: '1; mode=block' }];
    response.headers['strict-transport-security'] = [{ value: 'max-age=31536000; includeSubDomains' }];

    return response;
};
EOF

    cd "$lambda_dir" && zip -r edge-function.zip index.js && cd -

    edge_create "${stack_name}-security-headers" "viewer-response" "$lambda_dir/edge-function.zip"
    edge_publish "${stack_name}-security-headers"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment completed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Upload files: ./script.sh s3-sync ./your-site $bucket"
    echo "  2. Associate Lambda@Edge:"
    echo "     ./script.sh edge-associate <dist-id> <func-arn> viewer-response"
}

destroy() {
    local stack_name=$1
    log_warn "Deletion order:"
    echo "  1. Disassociate Lambda@Edge from CloudFront"
    echo "  2. Delete CloudFront distribution"
    echo "  3. Wait for replicas to be deleted (can take hours)"
    echo "  4. Delete Lambda@Edge function"
    echo "  5. Delete S3 bucket"
    echo "  6. Delete IAM role"
}

status() {
    echo -e "${BLUE}=== Lambda@Edge Functions (us-east-1) ===${NC}"
    edge_list
    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list
}

# Main
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
    edge-create) edge_create "$@" ;;
    edge-delete) edge_delete "$@" ;;
    edge-list) edge_list ;;
    edge-publish) edge_publish "$@" ;;
    edge-associate) edge_associate "$@" ;;
    edge-disassociate) edge_disassociate "$@" ;;
    s3-create) s3_create "$@" ;;
    s3-delete) s3_delete "$@" ;;
    s3-sync) s3_sync "$@" ;;
    cf-create) cf_create "$@" ;;
    cf-delete) cf_delete "$@" ;;
    cf-list) cf_list ;;
    cf-invalidate) cf_invalidate "$@" ;;
    *) log_error "Unknown command: $COMMAND"; usage ;;
esac
