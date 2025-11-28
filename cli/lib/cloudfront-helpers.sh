#!/bin/bash
# CloudFront helper functions for AWS CLI scripts
# Source this file after common.sh

# =============================================================================
# Distribution Operations
# =============================================================================

# Create a CloudFront distribution for S3
# Usage: cloudfront_create_s3_distribution <bucket-name> <oai-id> [comment]
# Returns: Distribution ID
cloudfront_create_s3_distribution() {
    local bucket_name="$1"
    local oai_id="$2"
    local comment="${3:-CloudFront distribution for $bucket_name}"
    local region=$(get_region)

    if [ -z "$bucket_name" ] || [ -z "$oai_id" ]; then
        log_error "Bucket name and OAI ID required"
        return 1
    fi

    log_step "Creating CloudFront distribution for: $bucket_name"

    local config=$(cat <<EOF
{
    "CallerReference": "$(date +%s)",
    "Comment": "$comment",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-$bucket_name",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
        },
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
            "Id": "S3-$bucket_name",
            "DomainName": "$bucket_name.s3.$region.amazonaws.com",
            "S3OriginConfig": {
                "OriginAccessIdentity": "origin-access-identity/cloudfront/$oai_id"
            }
        }]
    },
    "Enabled": true,
    "DefaultRootObject": "index.html",
    "PriceClass": "PriceClass_200",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021"
    }
}
EOF
)

    local dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$config" \
        --query 'Distribution.Id' \
        --output text)

    log_success "Distribution created: $dist_id"
    echo "$dist_id"
}

# Delete a CloudFront distribution
# Usage: cloudfront_delete_distribution <dist-id>
cloudfront_delete_distribution() {
    local dist_id="$1"

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID required"
        return 1
    fi

    log_step "Disabling distribution: $dist_id"

    # Get current config and ETag
    local config_output=$(aws cloudfront get-distribution-config --id "$dist_id")
    local etag=$(echo "$config_output" | jq -r '.ETag')
    local config=$(echo "$config_output" | jq '.DistributionConfig | .Enabled = false')

    # Disable distribution
    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$config"

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    # Get new ETag after disable
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    # Delete distribution
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"
    log_success "Distribution deleted: $dist_id"
}

# List CloudFront distributions
# Usage: cloudfront_list
cloudfront_list() {
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,Domain:DomainName,Status:Status,Enabled:Enabled}' \
        --output table
}

# Get distribution domain name
# Usage: cloudfront_get_domain <dist-id>
cloudfront_get_domain() {
    local dist_id="$1"
    aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DomainName' --output text
}

# Wait for distribution to be deployed
# Usage: cloudfront_wait_deployed <dist-id>
cloudfront_wait_deployed() {
    local dist_id="$1"
    log_info "Waiting for distribution deployment..."
    aws cloudfront wait distribution-deployed --id "$dist_id"
    log_success "Distribution deployed"
}

# =============================================================================
# Origin Access Identity Operations
# =============================================================================

# Create Origin Access Identity
# Usage: cloudfront_create_oai [comment]
# Returns: OAI ID
cloudfront_create_oai() {
    local comment="${1:-OAI for S3 access}"

    log_step "Creating Origin Access Identity"

    local oai_id=$(aws cloudfront create-cloud-front-origin-access-identity \
        --cloud-front-origin-access-identity-config "CallerReference=$(date +%s),Comment=$comment" \
        --query 'CloudFrontOriginAccessIdentity.Id' \
        --output text)

    log_success "OAI created: $oai_id"
    echo "$oai_id"
}

# Delete Origin Access Identity
# Usage: cloudfront_delete_oai <oai-id>
cloudfront_delete_oai() {
    local oai_id="$1"

    if [ -z "$oai_id" ]; then
        log_error "OAI ID required"
        return 1
    fi

    local etag=$(aws cloudfront get-cloud-front-origin-access-identity \
        --id "$oai_id" \
        --query 'ETag' \
        --output text)

    aws cloudfront delete-cloud-front-origin-access-identity --id "$oai_id" --if-match "$etag"
    log_success "OAI deleted: $oai_id"
}

# Get OAI canonical user ID for bucket policy
# Usage: cloudfront_get_oai_s3_user <oai-id>
cloudfront_get_oai_s3_user() {
    local oai_id="$1"
    aws cloudfront get-cloud-front-origin-access-identity \
        --id "$oai_id" \
        --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' \
        --output text
}

# =============================================================================
# Cache Invalidation
# =============================================================================

# Create cache invalidation
# Usage: cloudfront_invalidate <dist-id> [paths]
cloudfront_invalidate() {
    local dist_id="$1"
    local paths="${2:-/*}"

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID required"
        return 1
    fi

    log_step "Creating invalidation for: $paths"

    local invalidation_id=$(aws cloudfront create-invalidation \
        --distribution-id "$dist_id" \
        --paths "$paths" \
        --query 'Invalidation.Id' \
        --output text)

    log_success "Invalidation created: $invalidation_id"
    echo "$invalidation_id"
}

# =============================================================================
# S3 Bucket Policy for CloudFront
# =============================================================================

# Generate and apply S3 bucket policy for CloudFront OAI
# Usage: cloudfront_set_s3_bucket_policy <bucket-name> <oai-id>
cloudfront_set_s3_bucket_policy() {
    local bucket_name="$1"
    local oai_id="$2"

    if [ -z "$bucket_name" ] || [ -z "$oai_id" ]; then
        log_error "Bucket name and OAI ID required"
        return 1
    fi

    local canonical_user=$(cloudfront_get_oai_s3_user "$oai_id")

    local policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "AllowCloudFrontAccess",
        "Effect": "Allow",
        "Principal": {
            "CanonicalUser": "$canonical_user"
        },
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::$bucket_name/*"
    }]
}
EOF
)

    aws s3api put-bucket-policy --bucket "$bucket_name" --policy "$policy"
    log_success "Bucket policy applied for CloudFront access"
}
