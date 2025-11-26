#!/bin/bash

set -e

# S3 Operations Script
# Provides common S3 operations using AWS CLI

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list-buckets                        - List all S3 buckets"
    echo "  create-bucket <bucket-name>         - Create a new S3 bucket"
    echo "  delete-bucket <bucket-name>         - Delete an S3 bucket (must be empty)"
    echo "  list-objects <bucket-name>          - List objects in a bucket"
    echo "  upload <local-file> <bucket-name> [s3-key] - Upload a file to S3"
    echo "  download <bucket-name> <s3-key> [local-path] - Download a file from S3"
    echo "  delete-object <bucket-name> <s3-key> - Delete an object from S3"
    echo "  sync-upload <local-dir> <bucket-name> [prefix] - Sync local directory to S3"
    echo "  sync-download <bucket-name> <local-dir> [prefix] - Sync S3 to local directory"
    echo "  get-object-metadata <bucket-name> <s3-key> - Get object metadata"
    echo "  copy-object <src-bucket> <src-key> <dst-bucket> <dst-key> - Copy object within S3"
    echo "  make-public <bucket-name> <s3-key>  - Make an object publicly accessible"
    echo "  generate-presigned-url <bucket-name> <s3-key> [expiration] - Generate presigned URL (GET/download)"
    echo "  generate-presigned-put-url <bucket-name> <s3-key> [expiration] [content-type] - Generate presigned URL (PUT/upload)"
    echo "  upload-with-presigned-url <local-file> <presigned-url> [content-type] - Upload file using presigned URL"
    echo ""
    exit 1
}

# Function to check if bucket exists
bucket_exists() {
    local bucket_name=$1
    aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null
    return $?
}

# List all S3 buckets
list_buckets() {
    echo -e "${GREEN}Listing all S3 buckets...${NC}"
    aws s3 ls
}

# Create a new S3 bucket
create_bucket() {
    local bucket_name=$1
    if [ -z "$bucket_name" ]; then
        echo -e "${RED}Error: Bucket name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating bucket: $bucket_name${NC}"
    local region=${AWS_DEFAULT_REGION:-ap-northeast-1}

    if [ "$region" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name"
    else
        aws s3api create-bucket --bucket "$bucket_name" --region "$region" \
            --create-bucket-configuration LocationConstraint="$region"
    fi
    echo -e "${GREEN}Bucket created successfully${NC}"
}

# Delete an S3 bucket
delete_bucket() {
    local bucket_name=$1
    if [ -z "$bucket_name" ]; then
        echo -e "${RED}Error: Bucket name is required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete bucket: $bucket_name${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting bucket: $bucket_name${NC}"
    aws s3 rb "s3://$bucket_name" --force
    echo -e "${GREEN}Bucket deleted successfully${NC}"
}

# List objects in a bucket
list_objects() {
    local bucket_name=$1
    if [ -z "$bucket_name" ]; then
        echo -e "${RED}Error: Bucket name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing objects in bucket: $bucket_name${NC}"
    aws s3 ls "s3://$bucket_name" --recursive --human-readable --summarize
}

# Upload a file to S3
upload() {
    local local_file=$1
    local bucket_name=$2
    local s3_key=$3

    if [ -z "$local_file" ] || [ -z "$bucket_name" ]; then
        echo -e "${RED}Error: Local file and bucket name are required${NC}"
        exit 1
    fi

    if [ ! -f "$local_file" ]; then
        echo -e "${RED}Error: File does not exist: $local_file${NC}"
        exit 1
    fi

    if [ -z "$s3_key" ]; then
        s3_key=$(basename "$local_file")
    fi

    echo -e "${GREEN}Uploading $local_file to s3://$bucket_name/$s3_key${NC}"
    aws s3 cp "$local_file" "s3://$bucket_name/$s3_key"
    echo -e "${GREEN}Upload completed successfully${NC}"
}

# Download a file from S3
download() {
    local bucket_name=$1
    local s3_key=$2
    local local_path=$3

    if [ -z "$bucket_name" ] || [ -z "$s3_key" ]; then
        echo -e "${RED}Error: Bucket name and S3 key are required${NC}"
        exit 1
    fi

    if [ -z "$local_path" ]; then
        local_path=$(basename "$s3_key")
    fi

    echo -e "${GREEN}Downloading s3://$bucket_name/$s3_key to $local_path${NC}"
    aws s3 cp "s3://$bucket_name/$s3_key" "$local_path"
    echo -e "${GREEN}Download completed successfully${NC}"
}

# Delete an object from S3
delete_object() {
    local bucket_name=$1
    local s3_key=$2

    if [ -z "$bucket_name" ] || [ -z "$s3_key" ]; then
        echo -e "${RED}Error: Bucket name and S3 key are required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete s3://$bucket_name/$s3_key${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting object: s3://$bucket_name/$s3_key${NC}"
    aws s3 rm "s3://$bucket_name/$s3_key"
    echo -e "${GREEN}Object deleted successfully${NC}"
}

# Sync local directory to S3
sync_upload() {
    local local_dir=$1
    local bucket_name=$2
    local prefix=$3

    if [ -z "$local_dir" ] || [ -z "$bucket_name" ]; then
        echo -e "${RED}Error: Local directory and bucket name are required${NC}"
        exit 1
    fi

    if [ ! -d "$local_dir" ]; then
        echo -e "${RED}Error: Directory does not exist: $local_dir${NC}"
        exit 1
    fi

    local s3_path="s3://$bucket_name"
    if [ -n "$prefix" ]; then
        s3_path="$s3_path/$prefix"
    fi

    echo -e "${GREEN}Syncing $local_dir to $s3_path${NC}"
    aws s3 sync "$local_dir" "$s3_path" --delete
    echo -e "${GREEN}Sync completed successfully${NC}"
}

# Sync S3 to local directory
sync_download() {
    local bucket_name=$1
    local local_dir=$2
    local prefix=$3

    if [ -z "$bucket_name" ] || [ -z "$local_dir" ]; then
        echo -e "${RED}Error: Bucket name and local directory are required${NC}"
        exit 1
    fi

    local s3_path="s3://$bucket_name"
    if [ -n "$prefix" ]; then
        s3_path="$s3_path/$prefix"
    fi

    mkdir -p "$local_dir"

    echo -e "${GREEN}Syncing $s3_path to $local_dir${NC}"
    aws s3 sync "$s3_path" "$local_dir" --delete
    echo -e "${GREEN}Sync completed successfully${NC}"
}

# Get object metadata
get_object_metadata() {
    local bucket_name=$1
    local s3_key=$2

    if [ -z "$bucket_name" ] || [ -z "$s3_key" ]; then
        echo -e "${RED}Error: Bucket name and S3 key are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting metadata for s3://$bucket_name/$s3_key${NC}"
    aws s3api head-object --bucket "$bucket_name" --key "$s3_key"
}

# Copy object within S3
copy_object() {
    local src_bucket=$1
    local src_key=$2
    local dst_bucket=$3
    local dst_key=$4

    if [ -z "$src_bucket" ] || [ -z "$src_key" ] || [ -z "$dst_bucket" ] || [ -z "$dst_key" ]; then
        echo -e "${RED}Error: Source and destination bucket/key are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Copying s3://$src_bucket/$src_key to s3://$dst_bucket/$dst_key${NC}"
    aws s3 cp "s3://$src_bucket/$src_key" "s3://$dst_bucket/$dst_key"
    echo -e "${GREEN}Copy completed successfully${NC}"
}

# Make an object publicly accessible
make_public() {
    local bucket_name=$1
    local s3_key=$2

    if [ -z "$bucket_name" ] || [ -z "$s3_key" ]; then
        echo -e "${RED}Error: Bucket name and S3 key are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Making object public: s3://$bucket_name/$s3_key${NC}"
    aws s3api put-object-acl --bucket "$bucket_name" --key "$s3_key" --acl public-read
    echo -e "${GREEN}Object is now publicly accessible${NC}"
    echo -e "URL: https://$bucket_name.s3.amazonaws.com/$s3_key"
}

# Generate presigned URL (GET/download)
generate_presigned_url() {
    local bucket_name=$1
    local s3_key=$2
    local expiration=${3:-3600}

    if [ -z "$bucket_name" ] || [ -z "$s3_key" ]; then
        echo -e "${RED}Error: Bucket name and S3 key are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Generating presigned URL for download (expires in $expiration seconds)${NC}"
    aws s3 presign "s3://$bucket_name/$s3_key" --expires-in "$expiration"
}

# Generate presigned URL for PUT (upload)
generate_presigned_put_url() {
    local bucket_name=$1
    local s3_key=$2
    local expiration=${3:-3600}
    local content_type=${4:-"application/octet-stream"}

    if [ -z "$bucket_name" ] || [ -z "$s3_key" ]; then
        echo -e "${RED}Error: Bucket name and S3 key are required${NC}"
        exit 1
    fi

    # Check if Python3 and boto3 are available
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: python3 is required for generating PUT presigned URLs${NC}"
        exit 1
    fi

    if ! python3 -c "import boto3" &> /dev/null; then
        echo -e "${RED}Error: boto3 is required. Install with: pip3 install boto3${NC}"
        exit 1
    fi

    local region=${AWS_DEFAULT_REGION:-ap-northeast-1}

    echo -e "${GREEN}Generating presigned URL for upload (expires in $expiration seconds)${NC}"
    echo -e "${YELLOW}Content-Type: $content_type${NC}"

    python3 << EOF
import boto3
from botocore.config import Config

s3 = boto3.client('s3', region_name='${region}', config=Config(signature_version='s3v4'))
url = s3.generate_presigned_url(
    'put_object',
    Params={
        'Bucket': '${bucket_name}',
        'Key': '${s3_key}',
        'ContentType': '${content_type}'
    },
    ExpiresIn=${expiration}
)
print(url)
EOF

    echo ""
    echo -e "${GREEN}Usage example:${NC}"
    echo "curl -X PUT -H \"Content-Type: $content_type\" -T <local-file> \"<presigned-url>\""
}

# Upload file using presigned URL
upload_with_presigned_url() {
    local local_file=$1
    local presigned_url=$2
    local content_type=${3:-"application/octet-stream"}

    if [ -z "$local_file" ] || [ -z "$presigned_url" ]; then
        echo -e "${RED}Error: Local file and presigned URL are required${NC}"
        exit 1
    fi

    if [ ! -f "$local_file" ]; then
        echo -e "${RED}Error: File does not exist: $local_file${NC}"
        exit 1
    fi

    # Auto-detect content type if not specified
    if [ "$content_type" = "application/octet-stream" ]; then
        case "${local_file##*.}" in
            txt)  content_type="text/plain" ;;
            html) content_type="text/html" ;;
            css)  content_type="text/css" ;;
            js)   content_type="application/javascript" ;;
            json) content_type="application/json" ;;
            xml)  content_type="application/xml" ;;
            pdf)  content_type="application/pdf" ;;
            zip)  content_type="application/zip" ;;
            png)  content_type="image/png" ;;
            jpg|jpeg) content_type="image/jpeg" ;;
            gif)  content_type="image/gif" ;;
            svg)  content_type="image/svg+xml" ;;
            mp4)  content_type="video/mp4" ;;
            mp3)  content_type="audio/mpeg" ;;
        esac
    fi

    echo -e "${GREEN}Uploading $local_file using presigned URL${NC}"
    echo -e "${YELLOW}Content-Type: $content_type${NC}"

    local http_code
    http_code=$(curl -s -w "%{http_code}" -X PUT \
        -H "Content-Type: $content_type" \
        -T "$local_file" \
        "$presigned_url" \
        -o /dev/null)

    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}Upload completed successfully (HTTP $http_code)${NC}"
    else
        echo -e "${RED}Upload failed (HTTP $http_code)${NC}"
        exit 1
    fi
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    list-buckets)
        list_buckets
        ;;
    create-bucket)
        create_bucket "$@"
        ;;
    delete-bucket)
        delete_bucket "$@"
        ;;
    list-objects)
        list_objects "$@"
        ;;
    upload)
        upload "$@"
        ;;
    download)
        download "$@"
        ;;
    delete-object)
        delete_object "$@"
        ;;
    sync-upload)
        sync_upload "$@"
        ;;
    sync-download)
        sync_download "$@"
        ;;
    get-object-metadata)
        get_object_metadata "$@"
        ;;
    copy-object)
        copy_object "$@"
        ;;
    make-public)
        make_public "$@"
        ;;
    generate-presigned-url)
        generate_presigned_url "$@"
        ;;
    generate-presigned-put-url)
        generate_presigned_put_url "$@"
        ;;
    upload-with-presigned-url)
        upload_with_presigned_url "$@"
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac
