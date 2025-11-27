#!/bin/bash

set -e

# CloudFront → S3 Architecture Script
# Provides operations for static website hosting

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → S3 Static Website Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status <stack-name>                  - Show status of all components"
    echo ""
    echo "S3 Commands:"
    echo "  s3-create <bucket-name>              - Create S3 bucket for static hosting"
    echo "  s3-delete <bucket-name>              - Delete S3 bucket"
    echo "  s3-list                              - List S3 buckets"
    echo "  s3-sync <local-dir> <bucket>         - Sync local directory to S3"
    echo "  s3-upload <file> <bucket> [key]      - Upload file to S3"
    echo "  s3-website-enable <bucket>           - Enable static website hosting"
    echo "  s3-website-disable <bucket>          - Disable static website hosting"
    echo "  s3-policy-public <bucket>            - Set public read policy (for website)"
    echo "  s3-policy-cloudfront <bucket> <oai>  - Set CloudFront OAI policy"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <bucket> <stack-name>      - Create CloudFront distribution with OAI"
    echo "  cf-create-website <bucket-website-url> <stack-name> - Create CloudFront for S3 website endpoint"
    echo "  cf-delete <distribution-id>          - Delete CloudFront distribution"
    echo "  cf-list                              - List CloudFront distributions"
    echo "  cf-invalidate <dist-id> [path]       - Invalidate CloudFront cache"
    echo "  cf-status <dist-id>                  - Show distribution status"
    echo "  oai-create <comment>                 - Create Origin Access Identity"
    echo "  oai-delete <oai-id>                  - Delete Origin Access Identity"
    echo "  oai-list                             - List Origin Access Identities"
    echo ""
    exit 1
}

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check AWS CLI
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured"
        exit 1
    fi
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

    # Block public access by default (use OAI with CloudFront)
    aws s3api put-public-access-block \
        --bucket "$bucket" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    log_info "S3 bucket created: $bucket"
}

s3_delete() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_warn "This will delete bucket: $bucket and all its contents"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting S3 bucket: $bucket"
    aws s3 rb "s3://$bucket" --force
    log_info "Bucket deleted"
}

s3_list() {
    log_info "Listing S3 buckets..."
    aws s3 ls
}

s3_sync() {
    local local_dir=$1
    local bucket=$2

    if [ -z "$local_dir" ] || [ -z "$bucket" ]; then
        log_error "Local directory and bucket name are required"
        exit 1
    fi

    log_step "Syncing $local_dir to s3://$bucket"
    aws s3 sync "$local_dir" "s3://$bucket" --delete
    log_info "Sync completed"
}

s3_upload() {
    local file=$1
    local bucket=$2
    local key=${3:-$(basename "$file")}

    if [ -z "$file" ] || [ -z "$bucket" ]; then
        log_error "File and bucket name are required"
        exit 1
    fi

    log_step "Uploading $file to s3://$bucket/$key"
    aws s3 cp "$file" "s3://$bucket/$key"
    log_info "Upload completed"
}

s3_website_enable() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_step "Enabling static website hosting on: $bucket"

    aws s3 website "s3://$bucket" \
        --index-document index.html \
        --error-document error.html

    local website_url="http://$bucket.s3-website-$DEFAULT_REGION.amazonaws.com"
    log_info "Static website enabled"
    echo "Website URL: $website_url"
}

s3_website_disable() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_step "Disabling static website hosting"
    aws s3api delete-bucket-website --bucket "$bucket"
    log_info "Static website disabled"
}

s3_policy_public() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_warn "This will make the bucket publicly readable"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Setting public read policy"

    # Disable block public access
    aws s3api put-public-access-block \
        --bucket "$bucket" \
        --public-access-block-configuration \
            "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

    # Set bucket policy
    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "PublicReadGetObject",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::$bucket/*"
    }]
}
EOF
)

    aws s3api put-bucket-policy --bucket "$bucket" --policy "$policy"
    log_info "Public read policy set"
}

s3_policy_cloudfront() {
    local bucket=$1
    local oai_id=$2

    if [ -z "$bucket" ] || [ -z "$oai_id" ]; then
        log_error "Bucket name and OAI ID are required"
        exit 1
    fi

    log_step "Setting CloudFront OAI policy"

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "AllowCloudFrontOAI",
        "Effect": "Allow",
        "Principal": {
            "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $oai_id"
        },
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::$bucket/*"
    }]
}
EOF
)

    aws s3api put-bucket-policy --bucket "$bucket" --policy "$policy"
    log_info "CloudFront OAI policy set"
}

# ============================================
# CloudFront OAI Functions
# ============================================

oai_create() {
    local comment=${1:-"OAI for S3"}

    log_step "Creating Origin Access Identity"

    local oai_id
    oai_id=$(aws cloudfront create-cloud-front-origin-access-identity \
        --cloud-front-origin-access-identity-config "CallerReference=$(date +%s),Comment=$comment" \
        --query 'CloudFrontOriginAccessIdentity.Id' --output text)

    log_info "Created OAI: $oai_id"
    echo "$oai_id"
}

oai_delete() {
    local oai_id=$1

    if [ -z "$oai_id" ]; then
        log_error "OAI ID is required"
        exit 1
    fi

    log_step "Deleting OAI: $oai_id"

    local etag
    etag=$(aws cloudfront get-cloud-front-origin-access-identity \
        --id "$oai_id" --query 'ETag' --output text)

    aws cloudfront delete-cloud-front-origin-access-identity \
        --id "$oai_id" --if-match "$etag"

    log_info "OAI deleted"
}

oai_list() {
    log_info "Listing Origin Access Identities..."
    aws cloudfront list-cloud-front-origin-access-identities \
        --query 'CloudFrontOriginAccessIdentityList.Items[].{Id:Id,Comment:Comment}' \
        --output table
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

    log_step "Creating CloudFront distribution with OAI for: $bucket"

    # Create OAI
    local oai_id
    oai_id=$(oai_create "OAI for $stack_name")

    # Set bucket policy for OAI
    s3_policy_cloudfront "$bucket" "$oai_id"

    # Get OAI canonical user ID
    local oai_canonical
    oai_canonical=$(aws cloudfront get-cloud-front-origin-access-identity \
        --id "$oai_id" \
        --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' --output text)

    local dist_config=$(cat << EOF
{
    "CallerReference": "$stack_name-$(date +%s)",
    "Comment": "CloudFront for S3 $stack_name",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-$bucket",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": ["GET", "HEAD"],
        "CachedMethods": ["GET", "HEAD"],
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {"Forward": "none"}
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "S3-$bucket",
            "DomainName": "$bucket.s3.$DEFAULT_REGION.amazonaws.com",
            "S3OriginConfig": {
                "OriginAccessIdentity": "origin-access-identity/cloudfront/$oai_id"
            }
        }]
    },
    "DefaultRootObject": "index.html",
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [{
            "ErrorCode": 404,
            "ResponsePagePath": "/index.html",
            "ResponseCode": "200",
            "ErrorCachingMinTTL": 300
        }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_200"
}
EOF
)

    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --query 'Distribution.Id' --output text)

    local domain_name
    domain_name=$(aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.DomainName' --output text)

    echo ""
    echo -e "${GREEN}CloudFront Distribution Created${NC}"
    echo "Distribution ID: $dist_id"
    echo "Domain Name: $domain_name"
    echo "OAI ID: $oai_id"
}

cf_create_website() {
    local bucket_website_url=$1
    local stack_name=$2

    if [ -z "$bucket_website_url" ] || [ -z "$stack_name" ]; then
        log_error "S3 website URL and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution for S3 website endpoint"

    # Extract bucket name and region from URL
    local origin_domain
    origin_domain=$(echo "$bucket_website_url" | sed 's|http://||' | sed 's|/.*||')

    local dist_config=$(cat << EOF
{
    "CallerReference": "$stack_name-$(date +%s)",
    "Comment": "CloudFront for S3 Website $stack_name",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Website-$stack_name",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": ["GET", "HEAD"],
        "CachedMethods": ["GET", "HEAD"],
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {"Forward": "none"}
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "S3Website-$stack_name",
            "DomainName": "$origin_domain",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only",
                "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]}
            }
        }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_200"
}
EOF
)

    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --query 'Distribution.Id' --output text)

    local domain_name
    domain_name=$(aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.DomainName' --output text)

    echo ""
    echo -e "${GREEN}CloudFront Distribution Created${NC}"
    echo "Distribution ID: $dist_id"
    echo "Domain Name: $domain_name"
}

cf_delete() {
    local dist_id=$1

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_warn "This will delete CloudFront distribution: $dist_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Disabling distribution"

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
    log_info "Listing CloudFront distributions..."
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Enabled:Enabled}' \
        --output table
}

cf_invalidate() {
    local dist_id=$1
    local path=${2:-"/*"}

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_step "Creating invalidation for: $path"
    aws cloudfront create-invalidation --distribution-id "$dist_id" --paths "$path"
    log_info "Invalidation created"
}

cf_status() {
    local dist_id=$1

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.{Id:Id,Status:Status,DomainName:DomainName,Enabled:DistributionConfig.Enabled}' \
        --output table
}

# ============================================
# Full Stack Deploy/Destroy
# ============================================

deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_info "Deploying static website: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - S3 bucket for static files"
    echo "  - CloudFront distribution with OAI"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    local bucket_name="${stack_name}-static-$(date +%Y%m%d)"

    log_step "Step 1/2: Creating S3 bucket..."
    s3_create "$bucket_name"

    log_step "Step 2/2: Creating CloudFront distribution..."
    cf_create "$bucket_name" "$stack_name"

    echo ""
    echo -e "${GREEN}Deployment completed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Upload your static files:"
    echo "     ./script.sh s3-sync ./your-website-folder $bucket_name"
    echo ""
    echo "  2. Invalidate CloudFront cache after updates:"
    echo "     ./script.sh cf-invalidate <distribution-id>"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_warn "Deletion order for: $stack_name"
    echo ""
    echo "  1. Delete CloudFront distribution"
    echo "  2. Delete Origin Access Identity"
    echo "  3. Delete S3 bucket"
    echo ""

    log_info "Use individual delete commands"
}

status() {
    local stack_name=$1

    log_info "Checking status..."
    echo ""

    echo -e "${BLUE}=== S3 Buckets ===${NC}"
    s3_list

    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list

    echo -e "\n${BLUE}=== Origin Access Identities ===${NC}"
    oai_list
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

    s3-create) s3_create "$@" ;;
    s3-delete) s3_delete "$@" ;;
    s3-list) s3_list ;;
    s3-sync) s3_sync "$@" ;;
    s3-upload) s3_upload "$@" ;;
    s3-website-enable) s3_website_enable "$@" ;;
    s3-website-disable) s3_website_disable "$@" ;;
    s3-policy-public) s3_policy_public "$@" ;;
    s3-policy-cloudfront) s3_policy_cloudfront "$@" ;;

    cf-create) cf_create "$@" ;;
    cf-create-website) cf_create_website "$@" ;;
    cf-delete) cf_delete "$@" ;;
    cf-list) cf_list ;;
    cf-invalidate) cf_invalidate "$@" ;;
    cf-status) cf_status "$@" ;;

    oai-create) oai_create "$@" ;;
    oai-delete) oai_delete "$@" ;;
    oai-list) oai_list ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
