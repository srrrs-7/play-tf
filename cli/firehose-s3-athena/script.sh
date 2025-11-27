#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Kinesis Data Firehose → S3 → Athena Architecture Script
# Provides operations for real-time data ingestion and analytics

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Kinesis Data Firehose → S3 → Athena Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy streaming analytics stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "Firehose:"
    echo "  firehose-create <name> <bucket> [prefix]   - Create delivery stream"
    echo "  firehose-delete <name>                     - Delete delivery stream"
    echo "  firehose-list                              - List delivery streams"
    echo "  firehose-describe <name>                   - Describe delivery stream"
    echo "  put-record <stream> <data>                 - Put single record"
    echo "  put-records <stream> <file>                - Put records from file (JSON lines)"
    echo "  generate-data <stream> [count]             - Generate sample data"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  data-list <bucket> [prefix]                - List delivered data"
    echo ""
    echo "Glue Catalog:"
    echo "  database-create <name>                     - Create database"
    echo "  crawler-create <name> <bucket> <db>        - Create crawler"
    echo "  crawler-run <name>                         - Run crawler"
    echo "  tables-list <database>                     - List tables"
    echo ""
    echo "Athena:"
    echo "  workgroup-create <name> <bucket>           - Create workgroup"
    echo "  workgroup-delete <name>                    - Delete workgroup"
    echo "  query <database> <sql> [workgroup]         - Run query"
    echo "  query-status <query-id>                    - Get query status"
    echo "  query-results <query-id>                   - Get query results"
    echo ""
    exit 1
}

# Firehose Functions
firehose_create() {
    local name=$1
    local bucket=$2
    local prefix=${3:-"data"}

    if [ -z "$name" ] || [ -z "$bucket" ]; then
        log_error "Stream name and bucket required"
        exit 1
    fi

    log_step "Creating Firehose delivery stream: $name"
    local account_id=$(get_account_id)

    # Create IAM role for Firehose
    local role_name="${name}-firehose-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"firehose.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::$bucket",
                "arn:aws:s3:::$bucket/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": ["logs:PutLogEvents"],
            "Resource": "arn:aws:logs:$DEFAULT_REGION:$account_id:log-group:/aws/kinesisfirehose/$name:*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-access" --policy-document "$policy"

    sleep 10

    aws firehose create-delivery-stream \
        --delivery-stream-name "$name" \
        --delivery-stream-type DirectPut \
        --extended-s3-destination-configuration "{
            \"RoleARN\": \"arn:aws:iam::$account_id:role/$role_name\",
            \"BucketARN\": \"arn:aws:s3:::$bucket\",
            \"Prefix\": \"$prefix/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/\",
            \"ErrorOutputPrefix\": \"errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/\",
            \"BufferingHints\": {
                \"SizeInMBs\": 5,
                \"IntervalInSeconds\": 60
            },
            \"CompressionFormat\": \"GZIP\",
            \"CloudWatchLoggingOptions\": {
                \"Enabled\": true,
                \"LogGroupName\": \"/aws/kinesisfirehose/$name\",
                \"LogStreamName\": \"S3Delivery\"
            }
        }"

    log_info "Delivery stream created"
}

firehose_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }

    log_warn "Deleting delivery stream: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws firehose delete-delivery-stream --delivery-stream-name "$name"
    log_info "Delivery stream deleted"
}

firehose_list() {
    aws firehose list-delivery-streams --query 'DeliveryStreamNames[]' --output table
}

firehose_describe() {
    local name=$1
    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }
    aws firehose describe-delivery-stream --delivery-stream-name "$name" --output json
}

put_record() {
    local stream=$1
    local data=$2

    if [ -z "$stream" ] || [ -z "$data" ]; then
        log_error "Stream name and data required"
        exit 1
    fi

    aws firehose put-record \
        --delivery-stream-name "$stream" \
        --record "{\"Data\": \"$data\n\"}"
    log_info "Record sent"
}

put_records() {
    local stream=$1
    local file=$2

    if [ -z "$stream" ] || [ -z "$file" ]; then
        log_error "Stream name and file required"
        exit 1
    fi

    local records="["
    local first=true
    while IFS= read -r line; do
        if [ "$first" = true ]; then
            first=false
        else
            records+=","
        fi
        local encoded=$(echo -n "$line" | base64)
        records+="{\"Data\": \"$encoded\"}"
    done < "$file"
    records+="]"

    aws firehose put-record-batch --delivery-stream-name "$stream" --records "$records"
    log_info "Records batch sent"
}

generate_data() {
    local stream=$1
    local count=${2:-10}

    [ -z "$stream" ] && { log_error "Stream name required"; exit 1; }

    log_step "Generating $count sample records..."

    for i in $(seq 1 $count); do
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local event_types=("page_view" "click" "purchase" "signup" "logout")
        local event_type=${event_types[$((RANDOM % 5))]}
        local user_id="user_$((RANDOM % 1000))"
        local page_id="page_$((RANDOM % 50))"
        local value=$((RANDOM % 100))

        local record="{\"timestamp\":\"$timestamp\",\"event_type\":\"$event_type\",\"user_id\":\"$user_id\",\"page_id\":\"$page_id\",\"value\":$value}"

        aws firehose put-record \
            --delivery-stream-name "$stream" \
            --record "{\"Data\": \"$(echo -n "$record" | base64)\"}" > /dev/null

        echo "Sent: $record"
        sleep 0.1
    done

    log_info "Generated $count records"
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating bucket: $name"
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

    log_warn "Deleting bucket: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

data_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
    else
        aws s3 ls "s3://$bucket/" --recursive --human-readable
    fi
}

# Glue Functions
database_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Database name required"; exit 1; }
    aws glue create-database --database-input "{\"Name\": \"$name\"}"
    log_info "Database created"
}

crawler_create() {
    local name=$1
    local bucket=$2
    local database=$3

    if [ -z "$name" ] || [ -z "$bucket" ] || [ -z "$database" ]; then
        log_error "Crawler name, bucket, and database required"
        exit 1
    fi

    log_step "Creating crawler: $name"
    local account_id=$(get_account_id)

    local role_name="${name}-crawler-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket"],"Resource":["arn:aws:s3:::$bucket","arn:aws:s3:::$bucket/*"]}]}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3" --policy-document "$s3_policy"

    sleep 10

    aws glue create-crawler \
        --name "$name" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --database-name "$database" \
        --targets "{\"S3Targets\":[{\"Path\":\"s3://$bucket/data/\"}]}"

    log_info "Crawler created"
}

crawler_run() {
    local name=$1
    [ -z "$name" ] && { log_error "Crawler name required"; exit 1; }
    aws glue start-crawler --name "$name"
    log_info "Crawler started"
}

tables_list() {
    local database=$1
    [ -z "$database" ] && { log_error "Database name required"; exit 1; }
    aws glue get-tables --database-name "$database" --query 'TableList[].{Name:Name,Location:StorageDescriptor.Location}' --output table
}

# Athena Functions
workgroup_create() {
    local name=$1
    local bucket=$2

    if [ -z "$name" ] || [ -z "$bucket" ]; then
        log_error "Workgroup name and bucket required"
        exit 1
    fi

    aws athena create-work-group \
        --name "$name" \
        --configuration "{
            \"ResultConfiguration\": {
                \"OutputLocation\": \"s3://$bucket/athena-results/\"
            },
            \"EnforceWorkGroupConfiguration\": true,
            \"PublishCloudWatchMetricsEnabled\": true
        }"

    log_info "Workgroup created"
}

workgroup_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Workgroup name required"; exit 1; }
    aws athena delete-work-group --work-group "$name" --recursive-delete-option
    log_info "Workgroup deleted"
}

query() {
    local database=$1
    local sql=$2
    local workgroup=${3:-"primary"}

    if [ -z "$database" ] || [ -z "$sql" ]; then
        log_error "Database and SQL required"
        exit 1
    fi

    log_step "Executing query..."
    local query_id=$(aws athena start-query-execution \
        --query-string "$sql" \
        --query-execution-context "Database=$database" \
        --work-group "$workgroup" \
        --query 'QueryExecutionId' --output text)

    log_info "Query started: $query_id"

    echo "Waiting for completion..."
    for i in {1..60}; do
        local state=$(aws athena get-query-execution --query-execution-id "$query_id" --query 'QueryExecution.Status.State' --output text)
        if [ "$state" == "SUCCEEDED" ]; then
            echo -e "\n${GREEN}Query completed!${NC}"
            aws athena get-query-results --query-execution-id "$query_id" --output table
            return 0
        elif [ "$state" == "FAILED" ] || [ "$state" == "CANCELLED" ]; then
            local reason=$(aws athena get-query-execution --query-execution-id "$query_id" --query 'QueryExecution.Status.StateChangeReason' --output text)
            log_error "Query $state: $reason"
            return 1
        fi
        sleep 2
        echo -n "."
    done

    log_warn "Query still running: $query_id"
}

query_status() {
    local query_id=$1
    [ -z "$query_id" ] && { log_error "Query ID required"; exit 1; }
    aws athena get-query-execution --query-execution-id "$query_id" --output json
}

query_results() {
    local query_id=$1
    [ -z "$query_id" ] && { log_error "Query ID required"; exit 1; }
    aws athena get-query-results --query-execution-id "$query_id" --output table
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying Firehose → S3 → Athena stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-streaming-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Create Firehose role
    log_step "Creating IAM role..."
    local role_name="${name}-firehose-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"firehose.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:AbortMultipartUpload","s3:GetBucketLocation","s3:GetObject","s3:ListBucket","s3:ListBucketMultipartUploads","s3:PutObject"],
            "Resource": ["arn:aws:s3:::$bucket_name","arn:aws:s3:::$bucket_name/*"]
        },
        {
            "Effect": "Allow",
            "Action": ["logs:PutLogEvents"],
            "Resource": "arn:aws:logs:$DEFAULT_REGION:$account_id:log-group:/aws/kinesisfirehose/${name}-stream:*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3" --policy-document "$policy"

    sleep 10

    # Create Firehose delivery stream
    log_step "Creating Firehose delivery stream..."
    aws firehose create-delivery-stream \
        --delivery-stream-name "${name}-stream" \
        --delivery-stream-type DirectPut \
        --extended-s3-destination-configuration "{
            \"RoleARN\": \"arn:aws:iam::$account_id:role/$role_name\",
            \"BucketARN\": \"arn:aws:s3:::$bucket_name\",
            \"Prefix\": \"data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/\",
            \"ErrorOutputPrefix\": \"errors/!{firehose:error-output-type}/\",
            \"BufferingHints\": {\"SizeInMBs\": 5, \"IntervalInSeconds\": 60},
            \"CompressionFormat\": \"GZIP\",
            \"CloudWatchLoggingOptions\": {
                \"Enabled\": true,
                \"LogGroupName\": \"/aws/kinesisfirehose/${name}-stream\",
                \"LogStreamName\": \"S3Delivery\"
            }
        }" 2>/dev/null || log_info "Stream exists"

    # Create Glue database
    log_step "Creating Glue database..."
    aws glue create-database --database-input "{\"Name\": \"${name}_db\"}" 2>/dev/null || log_info "Database exists"

    # Create crawler role
    local crawler_role="${name}-crawler-role"
    aws iam create-role --role-name "$crawler_role" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}' 2>/dev/null || true
    aws iam attach-role-policy --role-name "$crawler_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local crawler_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket"],"Resource":["arn:aws:s3:::$bucket_name","arn:aws:s3:::$bucket_name/*"]}]}
EOF
)
    aws iam put-role-policy --role-name "$crawler_role" --policy-name "${name}-s3" --policy-document "$crawler_policy"

    sleep 5

    # Create crawler
    log_step "Creating Glue crawler..."
    aws glue create-crawler \
        --name "${name}-crawler" \
        --role "arn:aws:iam::$account_id:role/$crawler_role" \
        --database-name "${name}_db" \
        --targets "{\"S3Targets\":[{\"Path\":\"s3://$bucket_name/data/\"}]}" 2>/dev/null || log_info "Crawler exists"

    # Create Athena workgroup
    log_step "Creating Athena workgroup..."
    aws athena create-work-group \
        --name "${name}-workgroup" \
        --configuration "{
            \"ResultConfiguration\":{\"OutputLocation\":\"s3://$bucket_name/athena-results/\"},
            \"EnforceWorkGroupConfiguration\":true
        }" 2>/dev/null || log_info "Workgroup exists"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Firehose Stream: ${name}-stream"
    echo "Glue Database: ${name}_db"
    echo "Crawler: ${name}-crawler"
    echo "Athena Workgroup: ${name}-workgroup"
    echo ""
    echo "Generate sample data:"
    echo "  $0 generate-data ${name}-stream 100"
    echo ""
    echo "After data is delivered (1-2 minutes), run crawler:"
    echo "  $0 crawler-run ${name}-crawler"
    echo ""
    echo "Then query with Athena:"
    echo "  $0 query ${name}_db 'SELECT * FROM data LIMIT 10' ${name}-workgroup"
    echo ""
    echo "Sample analytics queries:"
    echo "  # Events by type"
    echo "  $0 query ${name}_db 'SELECT event_type, COUNT(*) as count FROM data GROUP BY event_type' ${name}-workgroup"
    echo ""
    echo "  # Events by hour"
    echo "  $0 query ${name}_db 'SELECT hour, COUNT(*) as count FROM data GROUP BY hour ORDER BY hour' ${name}-workgroup"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete Athena workgroup
    aws athena delete-work-group --work-group "${name}-workgroup" --recursive-delete-option 2>/dev/null || true

    # Delete Glue resources
    aws glue stop-crawler --name "${name}-crawler" 2>/dev/null || true
    aws glue delete-crawler --name "${name}-crawler" 2>/dev/null || true
    local tables=$(aws glue get-tables --database-name "${name}_db" --query 'TableList[].Name' --output text 2>/dev/null)
    for t in $tables; do
        aws glue delete-table --database-name "${name}_db" --name "$t" 2>/dev/null || true
    done
    aws glue delete-database --name "${name}_db" 2>/dev/null || true

    # Delete Firehose
    aws firehose delete-delivery-stream --delivery-stream-name "${name}-stream" 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-streaming-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete CloudWatch log group
    aws logs delete-log-group --log-group-name "/aws/kinesisfirehose/${name}-stream" 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-firehose-role" --policy-name "${name}-s3" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-firehose-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-crawler-role" --policy-name "${name}-s3" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-crawler-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-crawler-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Firehose Delivery Streams ===${NC}"
    firehose_list
    echo -e "\n${BLUE}=== Glue Databases ===${NC}"
    aws glue get-databases --query 'DatabaseList[].Name' --output table 2>/dev/null || echo "None"
    echo -e "\n${BLUE}=== Athena Workgroups ===${NC}"
    aws athena list-work-groups --query 'WorkGroups[].Name' --output table
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    firehose-create) firehose_create "$@" ;;
    firehose-delete) firehose_delete "$@" ;;
    firehose-list) firehose_list ;;
    firehose-describe) firehose_describe "$@" ;;
    put-record) put_record "$@" ;;
    put-records) put_records "$@" ;;
    generate-data) generate_data "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    data-list) data_list "$@" ;;
    database-create) database_create "$@" ;;
    crawler-create) crawler_create "$@" ;;
    crawler-run) crawler_run "$@" ;;
    tables-list) tables_list "$@" ;;
    workgroup-create) workgroup_create "$@" ;;
    workgroup-delete) workgroup_delete "$@" ;;
    query) query "$@" ;;
    query-status) query_status "$@" ;;
    query-results) query_results "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
