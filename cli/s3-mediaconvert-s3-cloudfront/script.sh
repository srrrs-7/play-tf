#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → MediaConvert → S3 → CloudFront Architecture Script
# Provides operations for video transcoding and delivery

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → MediaConvert → S3 → CloudFront Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy video processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3 (Input/Output):"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  upload-video <bucket> <file>               - Upload source video"
    echo "  list-videos <bucket> [prefix]              - List videos"
    echo ""
    echo "MediaConvert:"
    echo "  endpoints-list                             - List MediaConvert endpoints"
    echo "  queue-create <name>                        - Create queue"
    echo "  queue-delete <name>                        - Delete queue"
    echo "  queue-list                                 - List queues"
    echo "  job-create <input-bucket> <key> <output-bucket> - Create transcoding job"
    echo "  job-list                                   - List jobs"
    echo "  job-status <job-id>                        - Get job status"
    echo "  job-cancel <job-id>                        - Cancel job"
    echo "  template-create <name> <settings-file>     - Create job template"
    echo "  template-list                              - List templates"
    echo ""
    echo "CloudFront:"
    echo "  distribution-create <bucket> [name]        - Create distribution for output bucket"
    echo "  distribution-delete <id>                   - Delete distribution"
    echo "  distribution-list                          - List distributions"
    echo "  invalidate <dist-id> [path]                - Invalidate cache"
    echo ""
    exit 1
}

get_mediaconvert_endpoint() {
    aws mediaconvert describe-endpoints --query 'Endpoints[0].Url' --output text
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket --bucket "$name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi
    log_info "Bucket created"
}

bucket_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

upload_video() {
    local bucket=$1
    local file=$2

    if [ -z "$bucket" ] || [ -z "$file" ]; then
        log_error "Bucket and video file required"
        exit 1
    fi

    aws s3 cp "$file" "s3://$bucket/input/$(basename "$file")"
    log_info "Video uploaded to s3://$bucket/input/$(basename "$file")"
}

list_videos() {
    local bucket=$1
    local prefix=${2:-""}
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
    else
        aws s3 ls "s3://$bucket/" --recursive --human-readable
    fi
}

# MediaConvert Functions
endpoints_list() {
    aws mediaconvert describe-endpoints --output table
}

queue_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }

    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert create-queue --endpoint-url "$endpoint" --name "$name"
    log_info "Queue created"
}

queue_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }

    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert delete-queue --endpoint-url "$endpoint" --name "$name"
    log_info "Queue deleted"
}

queue_list() {
    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert list-queues --endpoint-url "$endpoint" --query 'Queues[].{Name:Name,Status:Status,Type:Type}' --output table
}

job_create() {
    local input_bucket=$1
    local key=$2
    local output_bucket=$3

    if [ -z "$input_bucket" ] || [ -z "$key" ] || [ -z "$output_bucket" ]; then
        log_error "Input bucket, key, and output bucket required"
        exit 1
    fi

    log_step "Creating transcoding job..."
    local account_id=$(get_account_id)
    local endpoint=$(get_mediaconvert_endpoint)

    # Create role if needed
    local role_name="MediaConvertRole"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"mediaconvert.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:GetObjectVersion"],
            "Resource": "arn:aws:s3:::$input_bucket/*"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject"],
            "Resource": "arn:aws:s3:::$output_bucket/*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "MediaConvertS3Access" --policy-document "$policy" 2>/dev/null || true

    sleep 5

    local basename=$(echo "$key" | sed 's/.*\///' | sed 's/\.[^.]*$//')

    local job_settings=$(cat << EOF
{
    "Role": "arn:aws:iam::$account_id:role/$role_name",
    "Settings": {
        "Inputs": [{
            "FileInput": "s3://$input_bucket/$key",
            "AudioSelectors": {
                "Audio Selector 1": {"DefaultSelection": "DEFAULT"}
            },
            "VideoSelector": {}
        }],
        "OutputGroups": [
            {
                "Name": "HLS",
                "OutputGroupSettings": {
                    "Type": "HLS_GROUP_SETTINGS",
                    "HlsGroupSettings": {
                        "Destination": "s3://$output_bucket/output/$basename/hls/",
                        "SegmentLength": 10,
                        "MinSegmentLength": 0
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_1080p",
                        "ContainerSettings": {"Container": "M3U8"},
                        "VideoDescription": {
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "MaxBitrate": 5000000,
                                    "QvbrSettings": {"QvbrQualityLevel": 7}
                                }
                            },
                            "Width": 1920,
                            "Height": 1080
                        },
                        "AudioDescriptions": [{
                            "CodecSettings": {
                                "Codec": "AAC",
                                "AacSettings": {"Bitrate": 128000, "SampleRate": 48000}
                            }
                        }]
                    },
                    {
                        "NameModifier": "_720p",
                        "ContainerSettings": {"Container": "M3U8"},
                        "VideoDescription": {
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "MaxBitrate": 2500000,
                                    "QvbrSettings": {"QvbrQualityLevel": 7}
                                }
                            },
                            "Width": 1280,
                            "Height": 720
                        },
                        "AudioDescriptions": [{
                            "CodecSettings": {
                                "Codec": "AAC",
                                "AacSettings": {"Bitrate": 96000, "SampleRate": 48000}
                            }
                        }]
                    }
                ]
            },
            {
                "Name": "MP4",
                "OutputGroupSettings": {
                    "Type": "FILE_GROUP_SETTINGS",
                    "FileGroupSettings": {
                        "Destination": "s3://$output_bucket/output/$basename/mp4/"
                    }
                },
                "Outputs": [{
                    "NameModifier": "_web",
                    "ContainerSettings": {"Container": "MP4", "Mp4Settings": {}},
                    "VideoDescription": {
                        "CodecSettings": {
                            "Codec": "H_264",
                            "H264Settings": {
                                "RateControlMode": "QVBR",
                                "MaxBitrate": 5000000,
                                "QvbrSettings": {"QvbrQualityLevel": 7}
                            }
                        },
                        "Width": 1920,
                        "Height": 1080
                    },
                    "AudioDescriptions": [{
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {"Bitrate": 128000, "SampleRate": 48000}
                        }
                    }]
                }]
            },
            {
                "Name": "Thumbnails",
                "OutputGroupSettings": {
                    "Type": "FILE_GROUP_SETTINGS",
                    "FileGroupSettings": {
                        "Destination": "s3://$output_bucket/output/$basename/thumbnails/"
                    }
                },
                "Outputs": [{
                    "NameModifier": "_thumb",
                    "ContainerSettings": {"Container": "RAW"},
                    "VideoDescription": {
                        "CodecSettings": {
                            "Codec": "FRAME_CAPTURE",
                            "FrameCaptureSettings": {
                                "FramerateNumerator": 1,
                                "FramerateDenominator": 10,
                                "MaxCaptures": 10,
                                "Quality": 80
                            }
                        },
                        "Width": 320,
                        "Height": 180
                    }
                }]
            }
        ]
    }
}
EOF
)

    local job_id=$(aws mediaconvert create-job \
        --endpoint-url "$endpoint" \
        --cli-input-json "$job_settings" \
        --query 'Job.Id' --output text)

    log_info "Job created: $job_id"
    echo "Job ID: $job_id"
    echo "Output will be at: s3://$output_bucket/output/$basename/"
}

job_list() {
    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert list-jobs --endpoint-url "$endpoint" --query 'Jobs[].{Id:Id,Status:Status,CreatedAt:CreatedAt}' --output table
}

job_status() {
    local job_id=$1
    [ -z "$job_id" ] && { log_error "Job ID required"; exit 1; }

    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert get-job --endpoint-url "$endpoint" --id "$job_id" --output json
}

job_cancel() {
    local job_id=$1
    [ -z "$job_id" ] && { log_error "Job ID required"; exit 1; }

    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert cancel-job --endpoint-url "$endpoint" --id "$job_id"
    log_info "Job cancelled"
}

template_create() {
    local name=$1
    local settings_file=$2

    if [ -z "$name" ] || [ -z "$settings_file" ]; then
        log_error "Template name and settings file required"
        exit 1
    fi

    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert create-job-template --endpoint-url "$endpoint" --name "$name" --settings "file://$settings_file"
    log_info "Template created"
}

template_list() {
    local endpoint=$(get_mediaconvert_endpoint)
    aws mediaconvert list-job-templates --endpoint-url "$endpoint" --query 'JobTemplates[].{Name:Name,Category:Category}' --output table
}

# CloudFront Functions
distribution_create() {
    local bucket=$1
    local name=${2:-"$bucket-distribution"}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating CloudFront distribution..."
    local account_id=$(get_account_id)

    # Create OAC
    local oac_id=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config "{
            \"Name\": \"${name}-oac\",
            \"SigningBehavior\": \"always\",
            \"SigningProtocol\": \"sigv4\",
            \"OriginAccessControlOriginType\": \"s3\"
        }" \
        --query 'OriginAccessControl.Id' --output text 2>/dev/null || \
        aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='${name}-oac'].Id" --output text)

    local config=$(cat << EOF
{
    "CallerReference": "$name-$(date +%s)",
    "Comment": "Distribution for $bucket",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-$bucket",
        "ViewerProtocolPolicy": "redirect-to-https",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "Compress": true,
        "AllowedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "S3-$bucket",
            "DomainName": "$bucket.s3.$DEFAULT_REGION.amazonaws.com",
            "OriginAccessControlId": "$oac_id",
            "S3OriginConfig": {"OriginAccessIdentity": ""}
        }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_All",
    "HttpVersion": "http2"
}
EOF
)

    local dist_id=$(aws cloudfront create-distribution --distribution-config "$config" --query 'Distribution.Id' --output text)
    local domain=$(aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DomainName' --output text)

    # Update S3 bucket policy for CloudFront
    local bucket_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "cloudfront.amazonaws.com"},
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::$bucket/*",
        "Condition": {
            "StringEquals": {"AWS:SourceArn": "arn:aws:cloudfront::$account_id:distribution/$dist_id"}
        }
    }]
}
EOF
)
    aws s3api put-bucket-policy --bucket "$bucket" --policy "$bucket_policy"

    log_info "Distribution created: $dist_id"
    echo "Domain: https://$domain"
}

distribution_delete() {
    local dist_id=$1
    [ -z "$dist_id" ] && { log_error "Distribution ID required"; exit 1; }

    log_warn "Deleting distribution: $dist_id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Disable first
    local config=$(aws cloudfront get-distribution-config --id "$dist_id")
    local etag=$(echo "$config" | jq -r '.ETag')
    local dist_config=$(echo "$config" | jq '.DistributionConfig.Enabled = false | .DistributionConfig')

    aws cloudfront update-distribution --id "$dist_id" --if-match "$etag" --distribution-config "$dist_config"

    log_info "Distribution disabled, waiting for deployment..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    local new_etag=$(aws cloudfront get-distribution --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$new_etag"
    log_info "Distribution deleted"
}

distribution_list() {
    aws cloudfront list-distributions --query 'DistributionList.Items[].{Id:Id,Domain:DomainName,Status:Status}' --output table
}

invalidate() {
    local dist_id=$1
    local path=${2:-"/*"}

    [ -z "$dist_id" ] && { log_error "Distribution ID required"; exit 1; }

    aws cloudfront create-invalidation --distribution-id "$dist_id" --paths "$path"
    log_info "Invalidation created for $path"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → MediaConvert → S3 → CloudFront stack: $name"
    local account_id=$(get_account_id)

    # Create input bucket
    log_step "Creating input S3 bucket..."
    local input_bucket="${name}-input-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$input_bucket" 2>/dev/null || log_info "Input bucket exists"
    else
        aws s3api create-bucket --bucket "$input_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Input bucket exists"
    fi

    # Create output bucket
    log_step "Creating output S3 bucket..."
    local output_bucket="${name}-output-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$output_bucket" 2>/dev/null || log_info "Output bucket exists"
    else
        aws s3api create-bucket --bucket "$output_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Output bucket exists"
    fi

    # Create MediaConvert role
    log_step "Creating MediaConvert IAM role..."
    local role_name="${name}-mediaconvert-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"mediaconvert.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {"Effect": "Allow", "Action": ["s3:GetObject", "s3:GetObjectVersion"], "Resource": "arn:aws:s3:::$input_bucket/*"},
        {"Effect": "Allow", "Action": ["s3:PutObject"], "Resource": "arn:aws:s3:::$output_bucket/*"}
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3" --policy-document "$policy"

    # Create CloudFront distribution
    log_step "Creating CloudFront distribution..."
    local oac_id=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config "{
            \"Name\": \"${name}-oac\",
            \"SigningBehavior\": \"always\",
            \"SigningProtocol\": \"sigv4\",
            \"OriginAccessControlOriginType\": \"s3\"
        }" \
        --query 'OriginAccessControl.Id' --output text 2>/dev/null || \
        aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='${name}-oac'].Id" --output text)

    local cf_config=$(cat << EOF
{
    "CallerReference": "$name-$(date +%s)",
    "Comment": "Video delivery for $name",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-$output_bucket",
        "ViewerProtocolPolicy": "redirect-to-https",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "Compress": true,
        "AllowedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "S3-$output_bucket",
            "DomainName": "$output_bucket.s3.$DEFAULT_REGION.amazonaws.com",
            "OriginAccessControlId": "$oac_id",
            "S3OriginConfig": {"OriginAccessIdentity": ""}
        }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "HttpVersion": "http2"
}
EOF
)

    local dist_id=$(aws cloudfront create-distribution --distribution-config "$cf_config" --query 'Distribution.Id' --output text 2>/dev/null || echo "")
    local cf_domain=""
    if [ -n "$dist_id" ]; then
        cf_domain=$(aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DomainName' --output text)

        # Update S3 bucket policy
        local bucket_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "cloudfront.amazonaws.com"},
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::$output_bucket/*",
        "Condition": {"StringEquals": {"AWS:SourceArn": "arn:aws:cloudfront::$account_id:distribution/$dist_id"}}
    }]
}
EOF
)
        aws s3api put-bucket-policy --bucket "$output_bucket" --policy "$bucket_policy"
    fi

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Input Bucket: $input_bucket"
    echo "Output Bucket: $output_bucket"
    echo "MediaConvert Role: $role_name"
    [ -n "$dist_id" ] && echo "CloudFront Distribution: $dist_id"
    [ -n "$cf_domain" ] && echo "CloudFront Domain: https://$cf_domain"
    echo ""
    echo "Upload and transcode a video:"
    echo "  # Upload video"
    echo "  $0 upload-video $input_bucket /path/to/video.mp4"
    echo ""
    echo "  # Create transcoding job"
    echo "  $0 job-create $input_bucket input/video.mp4 $output_bucket"
    echo ""
    echo "  # Check job status"
    echo "  $0 job-list"
    echo ""
    echo "  # Access transcoded video via CloudFront"
    [ -n "$cf_domain" ] && echo "  curl https://$cf_domain/output/video/mp4/video_web.mp4"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete CloudFront distribution
    local dist_id=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='Video delivery for $name'].Id" --output text 2>/dev/null)
    if [ -n "$dist_id" ] && [ "$dist_id" != "None" ]; then
        local config=$(aws cloudfront get-distribution-config --id "$dist_id")
        local etag=$(echo "$config" | jq -r '.ETag')
        local dist_config=$(echo "$config" | jq '.DistributionConfig.Enabled = false | .DistributionConfig')
        aws cloudfront update-distribution --id "$dist_id" --if-match "$etag" --distribution-config "$dist_config" 2>/dev/null || true
        log_info "Waiting for CloudFront to disable..."
        aws cloudfront wait distribution-deployed --id "$dist_id" 2>/dev/null || true
        local new_etag=$(aws cloudfront get-distribution --id "$dist_id" --query 'ETag' --output text)
        aws cloudfront delete-distribution --id "$dist_id" --if-match "$new_etag" 2>/dev/null || true
    fi

    # Delete OAC
    local oac_id=$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='${name}-oac'].Id" --output text 2>/dev/null)
    [ -n "$oac_id" ] && [ "$oac_id" != "None" ] && aws cloudfront delete-origin-access-control --id "$oac_id" 2>/dev/null || true

    # Delete S3 buckets
    local input_bucket="${name}-input-${account_id}"
    local output_bucket="${name}-output-${account_id}"
    aws s3 rb "s3://$input_bucket" --force 2>/dev/null || true
    aws s3 rb "s3://$output_bucket" --force 2>/dev/null || true

    # Delete IAM role
    aws iam delete-role-policy --role-name "${name}-mediaconvert-role" --policy-name "${name}-s3" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-mediaconvert-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== MediaConvert Endpoint ===${NC}"
    get_mediaconvert_endpoint
    echo -e "\n${BLUE}=== MediaConvert Jobs ===${NC}"
    job_list
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    distribution_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    upload-video) upload_video "$@" ;;
    list-videos) list_videos "$@" ;;
    endpoints-list) endpoints_list ;;
    queue-create) queue_create "$@" ;;
    queue-delete) queue_delete "$@" ;;
    queue-list) queue_list ;;
    job-create) job_create "$@" ;;
    job-list) job_list ;;
    job-status) job_status "$@" ;;
    job-cancel) job_cancel "$@" ;;
    template-create) template_create "$@" ;;
    template-list) template_list ;;
    distribution-create) distribution_create "$@" ;;
    distribution-delete) distribution_delete "$@" ;;
    distribution-list) distribution_list ;;
    invalidate) invalidate "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
