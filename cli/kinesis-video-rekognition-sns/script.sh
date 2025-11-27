#!/bin/bash
set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# =============================================================================
# Kinesis Video Streams → Rekognition → SNS Video Analysis Pipeline
# =============================================================================
# This script manages a video analysis infrastructure:
# - Kinesis Video Streams: Video ingestion
# - Rekognition Video: Face/object detection and analysis
# - SNS: Notifications for detected events
# =============================================================================

# Default region
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

# =============================================================================
# Usage Function
# =============================================================================
usage() {
    cat << EOF
Kinesis Video Streams → Rekognition → SNS Video Analysis Pipeline Management Script

Usage: $0 <command> [options]

Commands:
    deploy <stack-name>              Deploy the complete video analysis stack
    destroy <stack-name>             Destroy all resources for the stack
    status                           Show status of all components

    Kinesis Video Streams Commands:
    create-stream <name>             Create Kinesis Video stream
    delete-stream <arn>              Delete Kinesis Video stream
    list-streams                     List all Kinesis Video streams
    get-endpoint <stream-name>       Get data endpoint for stream
    get-hls-url <stream-name>        Get HLS playback URL

    Rekognition Commands:
    create-collection <name>         Create face collection
    delete-collection <id>           Delete face collection
    list-collections                 List all face collections
    index-faces <collection> <bucket> <key>  Index faces from S3 image
    list-faces <collection>          List faces in collection
    start-face-detection <stream> <collection>  Start face detection
    start-label-detection <stream>   Start label detection
    list-stream-processors           List stream processors
    stop-processor <name>            Stop stream processor
    delete-processor <name>          Delete stream processor

    SNS Commands:
    create-topic <name>              Create SNS topic
    subscribe <topic-arn> <email>    Subscribe email to topic
    list-topics                      List all SNS topics

Examples:
    $0 deploy my-video-analysis
    $0 create-stream security-camera-1
    $0 start-face-detection security-camera-1 my-faces
    $0 create-collection employees
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

# =============================================================================
# Kinesis Video Streams Functions
# =============================================================================
create_video_stream() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Stream name is required"
        exit 1
    fi

    log_step "Creating Kinesis Video stream: $name"

    aws kinesisvideo create-stream \
        --stream-name "$name" \
        --data-retention-in-hours 24 \
        --media-type "video/h264" \
        --output json | jq '.'

    log_info "Kinesis Video stream created successfully"
}

delete_video_stream() {
    local stream_arn=$1

    if [ -z "$stream_arn" ]; then
        log_error "Stream ARN is required"
        exit 1
    fi

    log_warn "This will delete the Kinesis Video stream"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting Kinesis Video stream..."
    aws kinesisvideo delete-stream --stream-arn "$stream_arn"

    log_info "Kinesis Video stream deleted successfully"
}

list_video_streams() {
    log_info "Listing Kinesis Video streams..."
    aws kinesisvideo list-streams \
        --query 'StreamInfoList[].{StreamName:StreamName,StreamARN:StreamARN,Status:Status,DataRetentionInHours:DataRetentionInHours}' \
        --output table
}

get_data_endpoint() {
    local stream_name=$1

    if [ -z "$stream_name" ]; then
        log_error "Stream name is required"
        exit 1
    fi

    log_info "Getting data endpoint for stream: $stream_name"
    aws kinesisvideo get-data-endpoint \
        --stream-name "$stream_name" \
        --api-name PUT_MEDIA \
        --output text
}

get_hls_url() {
    local stream_name=$1

    if [ -z "$stream_name" ]; then
        log_error "Stream name is required"
        exit 1
    fi

    log_info "Getting HLS playback URL for stream: $stream_name"

    # Get HLS streaming endpoint
    local endpoint=$(aws kinesisvideo get-data-endpoint \
        --stream-name "$stream_name" \
        --api-name GET_HLS_STREAMING_SESSION_URL \
        --query 'DataEndpoint' \
        --output text)

    # Get HLS URL
    aws kinesis-video-archived-media get-hls-streaming-session-url \
        --endpoint-url "$endpoint" \
        --stream-name "$stream_name" \
        --playback-mode LIVE \
        --query 'HLSStreamingSessionURL' \
        --output text
}

# =============================================================================
# Rekognition Functions
# =============================================================================
create_collection() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Collection name is required"
        exit 1
    fi

    log_step "Creating Rekognition collection: $name"

    aws rekognition create-collection \
        --collection-id "$name" \
        --output json | jq '.'

    log_info "Rekognition collection created successfully"
}

delete_collection() {
    local collection_id=$1

    if [ -z "$collection_id" ]; then
        log_error "Collection ID is required"
        exit 1
    fi

    log_warn "This will delete the collection: $collection_id"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting Rekognition collection..."
    aws rekognition delete-collection --collection-id "$collection_id"

    log_info "Rekognition collection deleted successfully"
}

list_collections() {
    log_info "Listing Rekognition collections..."
    aws rekognition list-collections \
        --query 'CollectionIds' \
        --output table
}

index_faces() {
    local collection_id=$1
    local bucket=$2
    local key=$3

    if [ -z "$collection_id" ] || [ -z "$bucket" ] || [ -z "$key" ]; then
        log_error "Collection ID, bucket, and key are required"
        exit 1
    fi

    log_step "Indexing faces from s3://${bucket}/${key}..."

    aws rekognition index-faces \
        --collection-id "$collection_id" \
        --image "{\"S3Object\":{\"Bucket\":\"$bucket\",\"Name\":\"$key\"}}" \
        --external-image-id "$(basename "$key" | cut -d. -f1)" \
        --detection-attributes "ALL" \
        --output json | jq '.'

    log_info "Faces indexed successfully"
}

list_faces() {
    local collection_id=$1

    if [ -z "$collection_id" ]; then
        log_error "Collection ID is required"
        exit 1
    fi

    log_info "Listing faces in collection: $collection_id"
    aws rekognition list-faces \
        --collection-id "$collection_id" \
        --query 'Faces[].{FaceId:FaceId,ExternalImageId:ExternalImageId,Confidence:Confidence}' \
        --output table
}

start_face_detection() {
    local stream_name=$1
    local collection_id=$2

    if [ -z "$stream_name" ] || [ -z "$collection_id" ]; then
        log_error "Stream name and collection ID are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION
    local processor_name="${stream_name}-face-processor"
    local role_arn="arn:aws:iam::${account_id}:role/${stream_name}-rekognition-role"
    local sns_topic_arn="arn:aws:sns:${region}:${account_id}:${stream_name}-notifications"

    # Get stream ARN
    local stream_arn=$(aws kinesisvideo describe-stream \
        --stream-name "$stream_name" \
        --query 'StreamInfo.StreamARN' \
        --output text)

    log_step "Creating stream processor: $processor_name"

    aws rekognition create-stream-processor \
        --name "$processor_name" \
        --input "{\"KinesisVideoStream\":{\"Arn\":\"$stream_arn\"}}" \
        --output "{\"KinesisDataStream\":{\"Arn\":\"arn:aws:kinesis:${region}:${account_id}:stream/${stream_name}-results\"}}" \
        --role-arn "$role_arn" \
        --settings "{\"FaceSearch\":{\"CollectionId\":\"$collection_id\",\"FaceMatchThreshold\":80}}" \
        --output json | jq '.'

    log_step "Starting stream processor..."
    aws rekognition start-stream-processor --name "$processor_name"

    log_info "Face detection started for stream: $stream_name"
}

start_label_detection() {
    local stream_name=$1

    if [ -z "$stream_name" ]; then
        log_error "Stream name is required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION
    local processor_name="${stream_name}-label-processor"
    local role_arn="arn:aws:iam::${account_id}:role/${stream_name}-rekognition-role"

    # Get stream ARN
    local stream_arn=$(aws kinesisvideo describe-stream \
        --stream-name "$stream_name" \
        --query 'StreamInfo.StreamARN' \
        --output text)

    log_step "Creating stream processor for label detection: $processor_name"

    aws rekognition create-stream-processor \
        --name "$processor_name" \
        --input "{\"KinesisVideoStream\":{\"Arn\":\"$stream_arn\"}}" \
        --output "{\"S3Destination\":{\"Bucket\":\"${stream_name}-results-${account_id}\",\"KeyPrefix\":\"labels/\"}}" \
        --role-arn "$role_arn" \
        --settings '{"ConnectedHome":{"Labels":["PERSON","PET","PACKAGE"],"MinConfidence":80}}' \
        --notification-channel "{\"SNSTopicArn\":\"arn:aws:sns:${region}:${account_id}:${stream_name}-notifications\"}" \
        --output json | jq '.'

    log_step "Starting stream processor..."
    aws rekognition start-stream-processor --name "$processor_name"

    log_info "Label detection started for stream: $stream_name"
}

list_stream_processors() {
    log_info "Listing stream processors..."
    aws rekognition list-stream-processors \
        --query 'StreamProcessors[].{Name:Name,Status:Status}' \
        --output table
}

stop_stream_processor() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Processor name is required"
        exit 1
    fi

    log_step "Stopping stream processor: $name"
    aws rekognition stop-stream-processor --name "$name"
    log_info "Stream processor stopped"
}

delete_stream_processor() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Processor name is required"
        exit 1
    fi

    log_warn "This will delete the stream processor: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Stop if running
    aws rekognition stop-stream-processor --name "$name" 2>/dev/null || true
    sleep 5

    log_step "Deleting stream processor: $name"
    aws rekognition delete-stream-processor --name "$name"
    log_info "Stream processor deleted"
}

# =============================================================================
# SNS Functions
# =============================================================================
create_sns_topic() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Topic name is required"
        exit 1
    fi

    log_step "Creating SNS topic: $name"

    local topic_arn=$(aws sns create-topic \
        --name "$name" \
        --query 'TopicArn' \
        --output text)

    log_info "SNS topic created: $topic_arn"
}

subscribe_email() {
    local topic_arn=$1
    local email=$2

    if [ -z "$topic_arn" ] || [ -z "$email" ]; then
        log_error "Topic ARN and email are required"
        exit 1
    fi

    log_step "Subscribing $email to topic..."

    aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol email \
        --notification-endpoint "$email" \
        --output json | jq '.'

    log_info "Subscription created. Check email to confirm."
}

list_sns_topics() {
    log_info "Listing SNS topics..."
    aws sns list-topics \
        --query 'Topics[].TopicArn' \
        --output table
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
    local region=$DEFAULT_REGION

    log_info "Deploying video analysis stack: $stack_name"
    echo ""

    # Step 1: Create IAM role for Rekognition
    log_step "Step 1: Creating IAM role for Rekognition..."

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "rekognition.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "${stack_name}-rekognition-role" \
        --assume-role-policy-document "$trust_policy" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    local rekognition_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "kinesisvideo:GetDataEndpoint",
                    "kinesisvideo:GetMedia"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "kinesis:PutRecord",
                    "kinesis:PutRecords"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:PutObject"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "sns:Publish"
                ],
                "Resource": "*"
            }
        ]
    }'

    aws iam put-role-policy \
        --role-name "${stack_name}-rekognition-role" \
        --policy-name "rekognition-access" \
        --policy-document "$rekognition_policy" 2>/dev/null || true

    sleep 10
    log_info "IAM role created"
    echo ""

    # Step 2: Create Kinesis Video Stream
    log_step "Step 2: Creating Kinesis Video stream..."

    aws kinesisvideo create-stream \
        --stream-name "$stack_name" \
        --data-retention-in-hours 24 \
        --media-type "video/h264" \
        --output json >/dev/null

    local stream_arn=$(aws kinesisvideo describe-stream \
        --stream-name "$stack_name" \
        --query 'StreamInfo.StreamARN' \
        --output text)

    log_info "Kinesis Video stream created: $stream_arn"
    echo ""

    # Step 3: Create Kinesis Data Stream for results
    log_step "Step 3: Creating Kinesis Data Stream for results..."

    aws kinesis create-stream \
        --stream-name "${stack_name}-results" \
        --shard-count 1 2>/dev/null || true

    aws kinesis wait stream-exists --stream-name "${stack_name}-results"
    log_info "Kinesis Data Stream created: ${stack_name}-results"
    echo ""

    # Step 4: Create S3 bucket for results
    log_step "Step 4: Creating S3 bucket for results..."

    local bucket_name="${stack_name}-results-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || true
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || true
    fi

    log_info "S3 bucket created: $bucket_name"
    echo ""

    # Step 5: Create SNS topic
    log_step "Step 5: Creating SNS topic..."

    local topic_arn=$(aws sns create-topic \
        --name "${stack_name}-notifications" \
        --query 'TopicArn' \
        --output text)

    log_info "SNS topic created: $topic_arn"
    echo ""

    # Step 6: Create Rekognition collection
    log_step "Step 6: Creating Rekognition collection..."

    aws rekognition create-collection \
        --collection-id "${stack_name}-faces" \
        --output json >/dev/null 2>&1 || true

    log_info "Face collection created: ${stack_name}-faces"
    echo ""

    log_info "================================================"
    log_info "Video analysis stack deployed successfully!"
    log_info "================================================"
    echo ""
    log_info "Stack Name: $stack_name"
    log_info "Video Stream: $stream_arn"
    log_info "Results Stream: ${stack_name}-results"
    log_info "Results Bucket: $bucket_name"
    log_info "SNS Topic: $topic_arn"
    log_info "Face Collection: ${stack_name}-faces"
    echo ""
    log_info "Next Steps:"
    log_info "1. Subscribe to notifications: $0 subscribe $topic_arn your@email.com"
    log_info "2. Index faces: $0 index-faces ${stack_name}-faces <bucket> <image-key>"
    log_info "3. Start face detection: $0 start-face-detection $stack_name ${stack_name}-faces"
    echo ""
    log_info "To stream video, get the data endpoint:"
    log_info "$0 get-endpoint $stack_name"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 destroy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION

    log_warn "This will destroy all resources for stack: $stack_name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Stop and delete stream processors
    log_step "Stopping stream processors..."
    local processors=$(aws rekognition list-stream-processors \
        --query "StreamProcessors[?starts_with(Name, '${stack_name}')].Name" \
        --output text 2>/dev/null || echo "")

    for processor in $processors; do
        aws rekognition stop-stream-processor --name "$processor" 2>/dev/null || true
        sleep 5
        aws rekognition delete-stream-processor --name "$processor" 2>/dev/null || true
    done

    # Delete Rekognition collection
    log_step "Deleting Rekognition collection..."
    aws rekognition delete-collection --collection-id "${stack_name}-faces" 2>/dev/null || true

    # Delete Kinesis Video Stream
    log_step "Deleting Kinesis Video stream..."
    local stream_arn=$(aws kinesisvideo describe-stream \
        --stream-name "$stack_name" \
        --query 'StreamInfo.StreamARN' \
        --output text 2>/dev/null || echo "")

    if [ -n "$stream_arn" ]; then
        aws kinesisvideo delete-stream --stream-arn "$stream_arn" 2>/dev/null || true
    fi

    # Delete Kinesis Data Stream
    log_step "Deleting Kinesis Data Stream..."
    aws kinesis delete-stream --stream-name "${stack_name}-results" 2>/dev/null || true

    # Delete S3 bucket
    log_step "Deleting S3 bucket..."
    local bucket_name="${stack_name}-results-${account_id}"
    aws s3 rb "s3://${bucket_name}" --force 2>/dev/null || true

    # Delete SNS topic
    log_step "Deleting SNS topic..."
    local topic_arn="arn:aws:sns:${region}:${account_id}:${stack_name}-notifications"
    aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || true

    # Delete IAM role
    log_step "Deleting IAM role..."
    aws iam delete-role-policy \
        --role-name "${stack_name}-rekognition-role" \
        --policy-name "rekognition-access" 2>/dev/null || true
    aws iam delete-role --role-name "${stack_name}-rekognition-role" 2>/dev/null || true

    log_info "Stack destroyed successfully: $stack_name"
}

status() {
    log_info "=== Video Analysis Stack Status ==="
    echo ""

    log_info "Kinesis Video Streams:"
    aws kinesisvideo list-streams \
        --query 'StreamInfoList[].{Name:StreamName,Status:Status,ARN:StreamARN}' \
        --output table 2>/dev/null || echo "No streams found"
    echo ""

    log_info "Rekognition Collections:"
    aws rekognition list-collections \
        --query 'CollectionIds' \
        --output table 2>/dev/null || echo "No collections found"
    echo ""

    log_info "Stream Processors:"
    aws rekognition list-stream-processors \
        --query 'StreamProcessors[].{Name:Name,Status:Status}' \
        --output table 2>/dev/null || echo "No processors found"
    echo ""

    log_info "SNS Topics:"
    aws sns list-topics \
        --query 'Topics[].TopicArn' \
        --output table 2>/dev/null || echo "No topics found"
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
    create-stream)
        create_video_stream "$@"
        ;;
    delete-stream)
        delete_video_stream "$@"
        ;;
    list-streams)
        list_video_streams
        ;;
    get-endpoint)
        get_data_endpoint "$@"
        ;;
    get-hls-url)
        get_hls_url "$@"
        ;;
    create-collection)
        create_collection "$@"
        ;;
    delete-collection)
        delete_collection "$@"
        ;;
    list-collections)
        list_collections
        ;;
    index-faces)
        index_faces "$@"
        ;;
    list-faces)
        list_faces "$@"
        ;;
    start-face-detection)
        start_face_detection "$@"
        ;;
    start-label-detection)
        start_label_detection "$@"
        ;;
    list-stream-processors)
        list_stream_processors
        ;;
    stop-processor)
        stop_stream_processor "$@"
        ;;
    delete-processor)
        delete_stream_processor "$@"
        ;;
    create-topic)
        create_sns_topic "$@"
        ;;
    subscribe)
        subscribe_email "$@"
        ;;
    list-topics)
        list_sns_topics
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
