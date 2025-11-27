#!/bin/bash
set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# =============================================================================
# CloudFront → MediaLive → MediaPackage → S3 Live Streaming Pipeline
# =============================================================================
# This script manages a live video streaming infrastructure:
# - MediaLive: Live video encoding
# - MediaPackage: Origin and packaging for multiple formats (HLS, DASH)
# - CloudFront: CDN for low-latency delivery
# - S3: Archive storage for recordings
# =============================================================================

# Default region
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

# =============================================================================
# Usage Function
# =============================================================================
usage() {
    cat << EOF
CloudFront → MediaLive → MediaPackage → S3 Live Streaming Pipeline Management Script

Usage: $0 <command> [options]

Commands:
    deploy <stack-name>              Deploy the complete live streaming stack
    destroy <stack-name>             Destroy all resources for the stack
    status                           Show status of all components

    MediaPackage Commands:
    create-channel <name>            Create MediaPackage channel
    delete-channel <channel-id>      Delete MediaPackage channel
    list-channels                    List all MediaPackage channels
    create-endpoint <channel-id> <type>  Create origin endpoint (HLS|DASH|CMAF)
    list-endpoints <channel-id>      List origin endpoints for channel

    MediaLive Commands:
    create-input <name> <type>       Create MediaLive input (RTMP_PUSH|RTP_PUSH|URL_PULL)
    delete-input <input-id>          Delete MediaLive input
    list-inputs                      List all MediaLive inputs
    create-channel-ml <name> <input-id> <mp-channel-id>  Create MediaLive channel
    delete-channel-ml <channel-id>   Delete MediaLive channel
    start-channel <channel-id>       Start MediaLive channel
    stop-channel <channel-id>        Stop MediaLive channel
    list-channels-ml                 List all MediaLive channels

    CloudFront Commands:
    create-distribution <origin-url> Create CloudFront distribution for streaming
    delete-distribution <dist-id>    Delete CloudFront distribution
    list-distributions               List all CloudFront distributions

    S3 Archive Commands:
    create-archive-bucket <name>     Create S3 bucket for recordings
    list-archives <bucket>           List archived recordings

Examples:
    $0 deploy my-live-stream
    $0 create-channel live-sports
    $0 start-channel 1234567
    $0 status

Environment Variables:
    AWS_DEFAULT_REGION    AWS region (default: ap-northeast-1)
    AWS_PROFILE           AWS profile to use

EOF
    exit 1
}

# =============================================================================
# Logging Functions
# =============================================================================

# =============================================================================
# Helper Functions
# =============================================================================

wait_for_medialive_channel() {
    local channel_id=$1
    local desired_state=$2
    local max_attempts=60
    local attempt=0

    log_info "Waiting for MediaLive channel to reach $desired_state state..."
    while [ $attempt -lt $max_attempts ]; do
        local state=$(aws medialive describe-channel \
            --channel-id "$channel_id" \
            --query 'State' \
            --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$state" == "$desired_state" ]; then
            log_info "Channel is now $desired_state"
            return 0
        fi

        echo -n "."
        sleep 10
        ((attempt++))
    done

    log_error "Timeout waiting for channel state: $desired_state"
    return 1
}

# =============================================================================
# MediaPackage Functions
# =============================================================================
create_mediapackage_channel() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Channel name is required"
        exit 1
    fi

    log_step "Creating MediaPackage channel: $name"

    local result=$(aws mediapackage create-channel \
        --id "$name" \
        --description "Live streaming channel: $name" \
        --output json)

    log_info "MediaPackage channel created successfully"
    echo "$result" | jq '.'

    # Extract ingest endpoints
    log_info "Ingest Endpoints:"
    echo "$result" | jq -r '.HlsIngest.IngestEndpoints[] | "URL: \(.Url)\nUsername: \(.Username)\nPassword: \(.Password)\n"'
}

delete_mediapackage_channel() {
    local channel_id=$1

    if [ -z "$channel_id" ]; then
        log_error "Channel ID is required"
        exit 1
    fi

    log_warn "This will delete the MediaPackage channel: $channel_id"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # First delete all origin endpoints
    local endpoints=$(aws mediapackage list-origin-endpoints \
        --channel-id "$channel_id" \
        --query 'OriginEndpoints[].Id' \
        --output text 2>/dev/null || echo "")

    for endpoint in $endpoints; do
        log_step "Deleting origin endpoint: $endpoint"
        aws mediapackage delete-origin-endpoint --id "$endpoint"
    done

    log_step "Deleting MediaPackage channel: $channel_id"
    aws mediapackage delete-channel --id "$channel_id"

    log_info "MediaPackage channel deleted successfully"
}

list_mediapackage_channels() {
    log_info "Listing MediaPackage channels..."
    aws mediapackage list-channels \
        --query 'Channels[].{Id:Id,Description:Description,Arn:Arn}' \
        --output table
}

create_origin_endpoint() {
    local channel_id=$1
    local endpoint_type=$2

    if [ -z "$channel_id" ] || [ -z "$endpoint_type" ]; then
        log_error "Channel ID and endpoint type are required"
        exit 1
    fi

    local endpoint_id="${channel_id}-${endpoint_type,,}"

    log_step "Creating origin endpoint: $endpoint_id"

    case $endpoint_type in
        HLS)
            aws mediapackage create-origin-endpoint \
                --channel-id "$channel_id" \
                --id "$endpoint_id" \
                --hls-package '{"SegmentDurationSeconds":6,"PlaylistWindowSeconds":60,"PlaylistType":"EVENT"}' \
                --output json | jq '.'
            ;;
        DASH)
            aws mediapackage create-origin-endpoint \
                --channel-id "$channel_id" \
                --id "$endpoint_id" \
                --dash-package '{"SegmentDurationSeconds":6,"ManifestWindowSeconds":60}' \
                --output json | jq '.'
            ;;
        CMAF)
            aws mediapackage create-origin-endpoint \
                --channel-id "$channel_id" \
                --id "$endpoint_id" \
                --cmaf-package '{"SegmentDurationSeconds":6,"HlsManifests":[{"Id":"cmaf-hls","IncludeIframeOnlyStream":false}]}' \
                --output json | jq '.'
            ;;
        *)
            log_error "Invalid endpoint type: $endpoint_type. Use HLS, DASH, or CMAF"
            exit 1
            ;;
    esac

    log_info "Origin endpoint created successfully"
}

list_origin_endpoints() {
    local channel_id=$1

    if [ -z "$channel_id" ]; then
        log_error "Channel ID is required"
        exit 1
    fi

    log_info "Listing origin endpoints for channel: $channel_id"
    aws mediapackage list-origin-endpoints \
        --channel-id "$channel_id" \
        --query 'OriginEndpoints[].{Id:Id,Url:Url,Type:to_string(HlsPackage!=`null` && `HLS` || DashPackage!=`null` && `DASH` || `CMAF`)}' \
        --output table
}

# =============================================================================
# MediaLive Functions
# =============================================================================
create_medialive_input() {
    local name=$1
    local input_type=$2

    if [ -z "$name" ] || [ -z "$input_type" ]; then
        log_error "Input name and type are required"
        exit 1
    fi

    log_step "Creating MediaLive input: $name (type: $input_type)"

    case $input_type in
        RTMP_PUSH)
            local sg_id=$(aws medialive create-input-security-group \
                --whitelist-rules '[{"Cidr":"0.0.0.0/0"}]' \
                --query 'SecurityGroup.Id' \
                --output text)

            aws medialive create-input \
                --name "$name" \
                --type "$input_type" \
                --input-security-groups "$sg_id" \
                --destinations '[{"StreamName":"live/stream"}]' \
                --output json | jq '.'
            ;;
        RTP_PUSH)
            local sg_id=$(aws medialive create-input-security-group \
                --whitelist-rules '[{"Cidr":"0.0.0.0/0"}]' \
                --query 'SecurityGroup.Id' \
                --output text)

            aws medialive create-input \
                --name "$name" \
                --type "$input_type" \
                --input-security-groups "$sg_id" \
                --output json | jq '.'
            ;;
        URL_PULL)
            read -p "Enter source URL: " source_url
            aws medialive create-input \
                --name "$name" \
                --type "$input_type" \
                --sources "[{\"Url\":\"$source_url\"}]" \
                --output json | jq '.'
            ;;
        *)
            log_error "Invalid input type: $input_type. Use RTMP_PUSH, RTP_PUSH, or URL_PULL"
            exit 1
            ;;
    esac

    log_info "MediaLive input created successfully"
}

delete_medialive_input() {
    local input_id=$1

    if [ -z "$input_id" ]; then
        log_error "Input ID is required"
        exit 1
    fi

    log_step "Deleting MediaLive input: $input_id"
    aws medialive delete-input --input-id "$input_id"
    log_info "MediaLive input deleted successfully"
}

list_medialive_inputs() {
    log_info "Listing MediaLive inputs..."
    aws medialive list-inputs \
        --query 'Inputs[].{Id:Id,Name:Name,Type:Type,State:State}' \
        --output table
}

create_medialive_channel() {
    local name=$1
    local input_id=$2
    local mp_channel_id=$3

    if [ -z "$name" ] || [ -z "$input_id" ] || [ -z "$mp_channel_id" ]; then
        log_error "Name, input ID, and MediaPackage channel ID are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION
    local role_arn="arn:aws:iam::${account_id}:role/${name}-medialive-role"

    # Create IAM role for MediaLive
    log_step "Creating IAM role for MediaLive..."

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "medialive.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "${name}-medialive-role" \
        --assume-role-policy-document "$trust_policy" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-medialive-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-medialive-role" \
        --policy-arn "arn:aws:iam::aws:policy/AWSElementalMediaPackageFullAccess" 2>/dev/null || true

    sleep 10

    # Get MediaPackage channel info
    local mp_info=$(aws mediapackage describe-channel --id "$mp_channel_id" --output json)
    local mp_url=$(echo "$mp_info" | jq -r '.HlsIngest.IngestEndpoints[0].Url')
    local mp_username=$(echo "$mp_info" | jq -r '.HlsIngest.IngestEndpoints[0].Username')
    local mp_password=$(echo "$mp_info" | jq -r '.HlsIngest.IngestEndpoints[0].Password')

    log_step "Creating MediaLive channel: $name"

    local input_attachment=$(jq -n \
        --arg input_id "$input_id" \
        --arg name "input-attachment" \
        '{
            "InputId": $input_id,
            "InputAttachmentName": $name,
            "InputSettings": {}
        }')

    local destination=$(jq -n \
        --arg url "$mp_url" \
        --arg user "$mp_username" \
        --arg pass "$mp_password" \
        '{
            "Id": "destination1",
            "Settings": [{
                "Url": $url,
                "Username": $user,
                "PasswordParam": $pass
            }]
        }')

    # Create channel with basic encoder settings
    aws medialive create-channel \
        --name "$name" \
        --channel-class "SINGLE_PIPELINE" \
        --input-attachments "[$input_attachment]" \
        --destinations "[$destination]" \
        --role-arn "$role_arn" \
        --encoder-settings '{
            "AudioDescriptions": [{
                "AudioSelectorName": "default",
                "CodecSettings": {
                    "AacSettings": {
                        "Bitrate": 128000,
                        "CodingMode": "CODING_MODE_2_0",
                        "InputType": "NORMAL",
                        "RawFormat": "NONE",
                        "SampleRate": 48000,
                        "Spec": "MPEG4"
                    }
                },
                "Name": "audio_1"
            }],
            "VideoDescriptions": [{
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 5000000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateDenominator": 1,
                        "FramerateNumerator": 30,
                        "GopSize": 2,
                        "GopSizeUnits": "SECONDS",
                        "Level": "H264_LEVEL_AUTO",
                        "Profile": "HIGH",
                        "RateControlMode": "CBR"
                    }
                },
                "Height": 1080,
                "Name": "video_1080p",
                "Width": 1920
            }],
            "OutputGroups": [{
                "OutputGroupSettings": {
                    "HlsGroupSettings": {
                        "Destination": {"DestinationRefId": "destination1"},
                        "HlsCdnSettings": {"HlsBasicPutSettings": {}},
                        "IndexNSegments": 10,
                        "KeepSegments": 21,
                        "SegmentLength": 6
                    }
                },
                "Outputs": [{
                    "AudioDescriptionNames": ["audio_1"],
                    "OutputSettings": {"HlsOutputSettings": {"HlsSettings": {"StandardHlsSettings": {"M3u8Settings": {}}}, "NameModifier": "_1080p"}},
                    "VideoDescriptionName": "video_1080p"
                }]
            }],
            "TimecodeConfig": {"Source": "SYSTEMCLOCK"}
        }' \
        --output json | jq '.'

    log_info "MediaLive channel created successfully"
}

delete_medialive_channel() {
    local channel_id=$1

    if [ -z "$channel_id" ]; then
        log_error "Channel ID is required"
        exit 1
    fi

    log_warn "This will delete the MediaLive channel: $channel_id"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Stop channel if running
    local state=$(aws medialive describe-channel \
        --channel-id "$channel_id" \
        --query 'State' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [ "$state" == "RUNNING" ]; then
        log_step "Stopping channel first..."
        aws medialive stop-channel --channel-id "$channel_id"
        wait_for_medialive_channel "$channel_id" "IDLE"
    fi

    log_step "Deleting MediaLive channel: $channel_id"
    aws medialive delete-channel --channel-id "$channel_id"

    log_info "MediaLive channel deleted successfully"
}

start_medialive_channel() {
    local channel_id=$1

    if [ -z "$channel_id" ]; then
        log_error "Channel ID is required"
        exit 1
    fi

    log_step "Starting MediaLive channel: $channel_id"
    aws medialive start-channel --channel-id "$channel_id"

    wait_for_medialive_channel "$channel_id" "RUNNING"
    log_info "MediaLive channel started successfully"
}

stop_medialive_channel() {
    local channel_id=$1

    if [ -z "$channel_id" ]; then
        log_error "Channel ID is required"
        exit 1
    fi

    log_step "Stopping MediaLive channel: $channel_id"
    aws medialive stop-channel --channel-id "$channel_id"

    wait_for_medialive_channel "$channel_id" "IDLE"
    log_info "MediaLive channel stopped successfully"
}

list_medialive_channels() {
    log_info "Listing MediaLive channels..."
    aws medialive list-channels \
        --query 'Channels[].{Id:Id,Name:Name,State:State,ChannelClass:ChannelClass}' \
        --output table
}

# =============================================================================
# CloudFront Functions
# =============================================================================
create_cloudfront_distribution() {
    local origin_url=$1

    if [ -z "$origin_url" ]; then
        log_error "Origin URL is required"
        exit 1
    fi

    log_step "Creating CloudFront distribution for: $origin_url"

    # Extract domain from URL
    local origin_domain=$(echo "$origin_url" | sed 's|https://||' | cut -d'/' -f1)
    local origin_path="/$(echo "$origin_url" | sed 's|https://||' | cut -d'/' -f2-)"

    local config=$(jq -n \
        --arg domain "$origin_domain" \
        --arg path "$origin_path" \
        --arg caller "cloudfront-medialive-$(date +%s)" \
        '{
            "CallerReference": $caller,
            "Comment": "Live streaming distribution",
            "Enabled": true,
            "Origins": {
                "Quantity": 1,
                "Items": [{
                    "Id": "mediapackage-origin",
                    "DomainName": $domain,
                    "OriginPath": "",
                    "CustomOriginConfig": {
                        "HTTPPort": 80,
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "https-only",
                        "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]}
                    }
                }]
            },
            "DefaultCacheBehavior": {
                "TargetOriginId": "mediapackage-origin",
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
                    "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
                },
                "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
                "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3",
                "Compress": true
            },
            "PriceClass": "PriceClass_All"
        }')

    aws cloudfront create-distribution \
        --distribution-config "$config" \
        --output json | jq '.'

    log_info "CloudFront distribution created successfully"
}

delete_cloudfront_distribution() {
    local dist_id=$1

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_warn "This will delete the CloudFront distribution: $dist_id"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Disable distribution first
    log_step "Disabling distribution..."
    local etag=$(aws cloudfront get-distribution --id "$dist_id" --query 'ETag' --output text)
    local config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)

    local disabled_config=$(echo "$config" | jq '.Enabled = false')
    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$disabled_config" >/dev/null

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    # Delete distribution
    log_step "Deleting distribution..."
    etag=$(aws cloudfront get-distribution --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"

    log_info "CloudFront distribution deleted successfully"
}

list_cloudfront_distributions() {
    log_info "Listing CloudFront distributions..."
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Enabled:Enabled}' \
        --output table
}

# =============================================================================
# S3 Archive Functions
# =============================================================================
create_archive_bucket() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    local bucket_name="${name}-archive-$(get_account_id)"

    log_step "Creating S3 archive bucket: $bucket_name"

    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    # Add lifecycle rule for cost optimization
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration '{
            "Rules": [{
                "ID": "ArchiveOldRecordings",
                "Status": "Enabled",
                "Filter": {"Prefix": "recordings/"},
                "Transitions": [
                    {"Days": 30, "StorageClass": "STANDARD_IA"},
                    {"Days": 90, "StorageClass": "GLACIER"}
                ]
            }]
        }'

    log_info "Archive bucket created: $bucket_name"
}

list_archives() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_info "Listing archives in bucket: $bucket"
    aws s3 ls "s3://${bucket}/recordings/" --recursive --human-readable
}

# =============================================================================
# Deploy/Destroy Functions
# =============================================================================
deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 deploy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)

    log_info "Deploying live streaming stack: $stack_name"
    echo ""

    # Step 1: Create S3 archive bucket
    log_step "Step 1: Creating S3 archive bucket..."
    create_archive_bucket "$stack_name"
    echo ""

    # Step 2: Create MediaPackage channel
    log_step "Step 2: Creating MediaPackage channel..."
    local mp_result=$(aws mediapackage create-channel \
        --id "${stack_name}-channel" \
        --description "Live streaming channel: $stack_name" \
        --output json)

    local mp_channel_id="${stack_name}-channel"
    log_info "MediaPackage channel created: $mp_channel_id"
    echo ""

    # Step 3: Create origin endpoints
    log_step "Step 3: Creating origin endpoints..."

    local hls_endpoint=$(aws mediapackage create-origin-endpoint \
        --channel-id "$mp_channel_id" \
        --id "${mp_channel_id}-hls" \
        --hls-package '{"SegmentDurationSeconds":6,"PlaylistWindowSeconds":60,"PlaylistType":"EVENT"}' \
        --output json)

    local hls_url=$(echo "$hls_endpoint" | jq -r '.Url')
    log_info "HLS endpoint: $hls_url"

    local dash_endpoint=$(aws mediapackage create-origin-endpoint \
        --channel-id "$mp_channel_id" \
        --id "${mp_channel_id}-dash" \
        --dash-package '{"SegmentDurationSeconds":6,"ManifestWindowSeconds":60}' \
        --output json)

    local dash_url=$(echo "$dash_endpoint" | jq -r '.Url')
    log_info "DASH endpoint: $dash_url"
    echo ""

    # Step 4: Create MediaLive input
    log_step "Step 4: Creating MediaLive input..."

    local sg_id=$(aws medialive create-input-security-group \
        --whitelist-rules '[{"Cidr":"0.0.0.0/0"}]' \
        --query 'SecurityGroup.Id' \
        --output text)

    local input_result=$(aws medialive create-input \
        --name "${stack_name}-input" \
        --type "RTMP_PUSH" \
        --input-security-groups "$sg_id" \
        --destinations '[{"StreamName":"live/stream"}]' \
        --output json)

    local input_id=$(echo "$input_result" | jq -r '.Input.Id')
    local rtmp_url=$(echo "$input_result" | jq -r '.Input.Destinations[0].Url')
    log_info "MediaLive input created: $input_id"
    log_info "RTMP ingest URL: $rtmp_url"
    echo ""

    # Step 5: Create CloudFront distribution
    log_step "Step 5: Creating CloudFront distribution..."

    local origin_domain=$(echo "$hls_url" | sed 's|https://||' | cut -d'/' -f1)

    local cf_config=$(jq -n \
        --arg domain "$origin_domain" \
        --arg caller "live-stream-$(date +%s)" \
        '{
            "CallerReference": $caller,
            "Comment": "Live streaming CDN for '"$stack_name"'",
            "Enabled": true,
            "Origins": {
                "Quantity": 1,
                "Items": [{
                    "Id": "mediapackage",
                    "DomainName": $domain,
                    "CustomOriginConfig": {
                        "HTTPPort": 80,
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "https-only",
                        "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]}
                    }
                }]
            },
            "DefaultCacheBehavior": {
                "TargetOriginId": "mediapackage",
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"], "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}},
                "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
                "Compress": true
            },
            "PriceClass": "PriceClass_All"
        }')

    local cf_result=$(aws cloudfront create-distribution \
        --distribution-config "$cf_config" \
        --output json)

    local cf_domain=$(echo "$cf_result" | jq -r '.Distribution.DomainName')
    local cf_id=$(echo "$cf_result" | jq -r '.Distribution.Id')
    log_info "CloudFront distribution: $cf_domain"
    echo ""

    log_info "================================================"
    log_info "Live streaming stack deployed successfully!"
    log_info "================================================"
    echo ""
    log_info "Stack Name: $stack_name"
    log_info "RTMP Ingest: $rtmp_url"
    log_info "HLS Playback: https://${cf_domain}/out/v1/${mp_channel_id}-hls/index.m3u8"
    log_info "DASH Playback: https://${cf_domain}/out/v1/${mp_channel_id}-dash/index.mpd"
    log_info "Archive Bucket: ${stack_name}-archive-${account_id}"
    echo ""
    log_warn "Note: MediaLive channel needs to be created separately with 'create-channel-ml' command"
    log_info "Note: CloudFront may take 10-15 minutes to fully deploy"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 destroy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)

    log_warn "This will destroy all resources for stack: $stack_name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Delete MediaLive resources
    log_step "Checking for MediaLive channels..."
    local ml_channels=$(aws medialive list-channels \
        --query "Channels[?starts_with(Name, '${stack_name}')].Id" \
        --output text 2>/dev/null || echo "")

    for channel_id in $ml_channels; do
        local state=$(aws medialive describe-channel \
            --channel-id "$channel_id" \
            --query 'State' \
            --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$state" == "RUNNING" ]; then
            log_step "Stopping MediaLive channel: $channel_id"
            aws medialive stop-channel --channel-id "$channel_id"
            wait_for_medialive_channel "$channel_id" "IDLE"
        fi

        log_step "Deleting MediaLive channel: $channel_id"
        aws medialive delete-channel --channel-id "$channel_id" 2>/dev/null || true
    done

    # Delete MediaLive inputs
    log_step "Checking for MediaLive inputs..."
    local ml_inputs=$(aws medialive list-inputs \
        --query "Inputs[?starts_with(Name, '${stack_name}')].Id" \
        --output text 2>/dev/null || echo "")

    for input_id in $ml_inputs; do
        log_step "Deleting MediaLive input: $input_id"
        aws medialive delete-input --input-id "$input_id" 2>/dev/null || true
    done

    # Delete CloudFront distributions
    log_step "Checking for CloudFront distributions..."
    local cf_dists=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?contains(Comment, '${stack_name}')].Id" \
        --output text 2>/dev/null || echo "")

    for dist_id in $cf_dists; do
        log_step "Disabling CloudFront distribution: $dist_id"
        local etag=$(aws cloudfront get-distribution --id "$dist_id" --query 'ETag' --output text)
        local config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)
        local disabled_config=$(echo "$config" | jq '.Enabled = false')
        aws cloudfront update-distribution \
            --id "$dist_id" \
            --if-match "$etag" \
            --distribution-config "$disabled_config" 2>/dev/null || true
    done

    # Delete MediaPackage endpoints and channel
    log_step "Deleting MediaPackage resources..."
    local mp_channel_id="${stack_name}-channel"

    aws mediapackage delete-origin-endpoint --id "${mp_channel_id}-hls" 2>/dev/null || true
    aws mediapackage delete-origin-endpoint --id "${mp_channel_id}-dash" 2>/dev/null || true
    aws mediapackage delete-channel --id "$mp_channel_id" 2>/dev/null || true

    # Delete S3 archive bucket
    log_step "Deleting S3 archive bucket..."
    local bucket_name="${stack_name}-archive-${account_id}"
    aws s3 rb "s3://${bucket_name}" --force 2>/dev/null || true

    # Delete IAM role
    log_step "Deleting IAM role..."
    aws iam detach-role-policy \
        --role-name "${stack_name}-medialive-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${stack_name}-medialive-role" \
        --policy-arn "arn:aws:iam::aws:policy/AWSElementalMediaPackageFullAccess" 2>/dev/null || true
    aws iam delete-role --role-name "${stack_name}-medialive-role" 2>/dev/null || true

    log_info "Stack destroyed successfully: $stack_name"
    log_warn "Note: CloudFront distributions may take time to fully delete after being disabled"
}

status() {
    log_info "=== Live Streaming Stack Status ==="
    echo ""

    log_info "MediaPackage Channels:"
    aws mediapackage list-channels \
        --query 'Channels[].{Id:Id,Description:Description}' \
        --output table 2>/dev/null || echo "No channels found"
    echo ""

    log_info "MediaLive Inputs:"
    aws medialive list-inputs \
        --query 'Inputs[].{Id:Id,Name:Name,Type:Type,State:State}' \
        --output table 2>/dev/null || echo "No inputs found"
    echo ""

    log_info "MediaLive Channels:"
    aws medialive list-channels \
        --query 'Channels[].{Id:Id,Name:Name,State:State}' \
        --output table 2>/dev/null || echo "No channels found"
    echo ""

    log_info "CloudFront Distributions:"
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,Domain:DomainName,Status:Status}' \
        --output table 2>/dev/null || echo "No distributions found"
}

# =============================================================================
# Main
# =============================================================================
check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    deploy)
        deploy "$@"
        ;;
    destroy)
        destroy "$@"
        ;;
    status)
        status
        ;;
    create-channel)
        create_mediapackage_channel "$@"
        ;;
    delete-channel)
        delete_mediapackage_channel "$@"
        ;;
    list-channels)
        list_mediapackage_channels
        ;;
    create-endpoint)
        create_origin_endpoint "$@"
        ;;
    list-endpoints)
        list_origin_endpoints "$@"
        ;;
    create-input)
        create_medialive_input "$@"
        ;;
    delete-input)
        delete_medialive_input "$@"
        ;;
    list-inputs)
        list_medialive_inputs
        ;;
    create-channel-ml)
        create_medialive_channel "$@"
        ;;
    delete-channel-ml)
        delete_medialive_channel "$@"
        ;;
    start-channel)
        start_medialive_channel "$@"
        ;;
    stop-channel)
        stop_medialive_channel "$@"
        ;;
    list-channels-ml)
        list_medialive_channels
        ;;
    create-distribution)
        create_cloudfront_distribution "$@"
        ;;
    delete-distribution)
        delete_cloudfront_distribution "$@"
        ;;
    list-distributions)
        list_cloudfront_distributions
        ;;
    create-archive-bucket)
        create_archive_bucket "$@"
        ;;
    list-archives)
        list_archives "$@"
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
