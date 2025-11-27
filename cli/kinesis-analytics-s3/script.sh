#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Kinesis Data Streams → Kinesis Data Analytics → S3 Architecture Script
# Provides operations for real-time stream analytics

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Kinesis Data Streams → Kinesis Data Analytics → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy stream analytics stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "Kinesis Data Streams:"
    echo "  stream-create <name> [shards]              - Create data stream"
    echo "  stream-delete <name>                       - Delete stream"
    echo "  stream-list                                - List streams"
    echo "  put-record <stream> <data> <pk>            - Put record"
    echo "  generate-data <stream> [count]             - Generate sample data"
    echo ""
    echo "Kinesis Data Analytics (Managed Apache Flink):"
    echo "  app-create <name> <stream> <bucket>        - Create Flink application"
    echo "  app-delete <name>                          - Delete application"
    echo "  app-list                                   - List applications"
    echo "  app-describe <name>                        - Describe application"
    echo "  app-start <name>                           - Start application"
    echo "  app-stop <name>                            - Stop application"
    echo "  app-update <name> <jar-s3-path>            - Update application code"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  bucket-list                                - List buckets"
    echo "  output-list <bucket> [prefix]              - List output data"
    echo ""
    exit 1
}

# Kinesis Data Streams Functions
stream_create() {
    local name=$1
    local shards=${2:-1}

    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }

    log_step "Creating Kinesis stream: $name with $shards shard(s)"
    aws kinesis create-stream --stream-name "$name" --shard-count "$shards"

    log_info "Waiting for stream to become active..."
    aws kinesis wait stream-exists --stream-name "$name"
    log_info "Stream created"
}

stream_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }

    log_warn "Deleting stream: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws kinesis delete-stream --stream-name "$name"
    log_info "Stream deleted"
}

stream_list() {
    aws kinesis list-streams --query 'StreamNames[]' --output table
}

put_record() {
    local stream=$1
    local data=$2
    local pk=$3

    if [ -z "$stream" ] || [ -z "$data" ] || [ -z "$pk" ]; then
        log_error "Stream, data, and partition key required"
        exit 1
    fi

    aws kinesis put-record --stream-name "$stream" --data "$data" --partition-key "$pk"
    log_info "Record sent"
}

generate_data() {
    local stream=$1
    local count=${2:-100}

    [ -z "$stream" ] && { log_error "Stream name required"; exit 1; }

    log_step "Generating $count sample records..."

    for i in $(seq 1 $count); do
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local sensors=("temperature" "humidity" "pressure" "co2")
        local sensor=${sensors[$((RANDOM % 4))]}
        local device_id="device_$((RANDOM % 10))"
        local value=$(echo "scale=2; $RANDOM / 100" | bc)
        local location=("building_a" "building_b" "warehouse" "factory")
        local loc=${location[$((RANDOM % 4))]}

        local record="{\"timestamp\":\"$timestamp\",\"sensor_type\":\"$sensor\",\"device_id\":\"$device_id\",\"value\":$value,\"location\":\"$loc\"}"

        aws kinesis put-record \
            --stream-name "$stream" \
            --data "$record" \
            --partition-key "$device_id" > /dev/null

        if [ $((i % 10)) -eq 0 ]; then
            echo "Sent $i/$count records..."
        fi
        sleep 0.05
    done

    log_info "Generated $count records"
}

# Kinesis Data Analytics Functions
app_create() {
    local name=$1
    local stream=$2
    local bucket=$3

    if [ -z "$name" ] || [ -z "$stream" ] || [ -z "$bucket" ]; then
        log_error "Application name, stream name, and bucket required"
        exit 1
    fi

    log_step "Creating Kinesis Analytics application: $name"
    local account_id=$(get_account_id)

    # Get stream ARN
    local stream_arn=$(aws kinesis describe-stream --stream-name "$stream" --query 'StreamDescription.StreamARN' --output text)

    # Create IAM role
    local role_name="${name}-kda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"kinesisanalytics.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListShards"
            ],
            "Resource": "$stream_arn"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::$bucket",
                "arn:aws:s3:::$bucket/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream"
            ],
            "Resource": "arn:aws:logs:$DEFAULT_REGION:$account_id:*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-policy" --policy-document "$policy"

    sleep 10

    # Note: This creates a SQL-based analytics application (v1)
    # For Flink applications (v2), use kinesisanalyticsv2 API
    aws kinesisanalytics create-application \
        --application-name "$name" \
        --application-description "Stream analytics for $stream" \
        --inputs "[{
            \"NamePrefix\": \"SOURCE_SQL_STREAM\",
            \"KinesisStreamsInput\": {
                \"ResourceARN\": \"$stream_arn\",
                \"RoleARN\": \"arn:aws:iam::$account_id:role/$role_name\"
            },
            \"InputSchema\": {
                \"RecordFormat\": {
                    \"RecordFormatType\": \"JSON\",
                    \"MappingParameters\": {
                        \"JSONMappingParameters\": {
                            \"RecordRowPath\": \"\$\"
                        }
                    }
                },
                \"RecordColumns\": [
                    {\"Name\": \"timestamp\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.timestamp\"},
                    {\"Name\": \"sensor_type\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.sensor_type\"},
                    {\"Name\": \"device_id\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.device_id\"},
                    {\"Name\": \"value\", \"SqlType\": \"DOUBLE\", \"Mapping\": \"\$.value\"},
                    {\"Name\": \"location\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.location\"}
                ]
            }
        }]" \
        --application-code "
CREATE OR REPLACE STREAM \"DESTINATION_SQL_STREAM\" (
    sensor_type VARCHAR(32),
    location VARCHAR(32),
    avg_value DOUBLE,
    min_value DOUBLE,
    max_value DOUBLE,
    record_count INTEGER,
    window_end TIMESTAMP
);

CREATE OR REPLACE PUMP \"STREAM_PUMP\" AS
INSERT INTO \"DESTINATION_SQL_STREAM\"
SELECT STREAM
    sensor_type,
    location,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    COUNT(*) AS record_count,
    STEP(\"SOURCE_SQL_STREAM_001\".ROWTIME BY INTERVAL '60' SECOND) AS window_end
FROM \"SOURCE_SQL_STREAM_001\"
GROUP BY
    sensor_type,
    location,
    STEP(\"SOURCE_SQL_STREAM_001\".ROWTIME BY INTERVAL '60' SECOND);
"

    log_info "Application created"
}

app_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Application name required"; exit 1; }

    # Get create timestamp
    local create_timestamp=$(aws kinesisanalytics describe-application --application-name "$name" --query 'ApplicationDetail.CreateTimestamp' --output text 2>/dev/null)

    if [ -n "$create_timestamp" ] && [ "$create_timestamp" != "None" ]; then
        aws kinesisanalytics delete-application --application-name "$name" --create-timestamp "$create_timestamp"
        log_info "Application deleted"
    else
        log_warn "Application not found"
    fi
}

app_list() {
    aws kinesisanalytics list-applications --query 'ApplicationSummaries[].{Name:ApplicationName,Status:ApplicationStatus}' --output table
}

app_describe() {
    local name=$1
    [ -z "$name" ] && { log_error "Application name required"; exit 1; }
    aws kinesisanalytics describe-application --application-name "$name" --output json
}

app_start() {
    local name=$1
    [ -z "$name" ] && { log_error "Application name required"; exit 1; }

    local input_id=$(aws kinesisanalytics describe-application --application-name "$name" --query 'ApplicationDetail.InputDescriptions[0].InputId' --output text)

    aws kinesisanalytics start-application \
        --application-name "$name" \
        --input-configurations "[{\"Id\": \"$input_id\", \"InputStartingPositionConfiguration\": {\"InputStartingPosition\": \"NOW\"}}]"

    log_info "Application starting"
}

app_stop() {
    local name=$1
    [ -z "$name" ] && { log_error "Application name required"; exit 1; }
    aws kinesisanalytics stop-application --application-name "$name"
    log_info "Application stopping"
}

app_update() {
    local name=$1
    local code_path=$2

    if [ -z "$name" ] || [ -z "$code_path" ]; then
        log_error "Application name and S3 code path required"
        exit 1
    fi

    local current_version=$(aws kinesisanalytics describe-application --application-name "$name" --query 'ApplicationDetail.ApplicationVersionId' --output text)

    aws kinesisanalytics update-application \
        --application-name "$name" \
        --current-application-version-id "$current_version" \
        --application-update "{\"ApplicationCodeUpdate\": \"$(cat "$code_path")\"}"

    log_info "Application updated"
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

bucket_list() {
    aws s3api list-buckets --query 'Buckets[].Name' --output table
}

output_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
    else
        aws s3 ls "s3://$bucket/" --recursive --human-readable
    fi
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying Kinesis Streams → Analytics → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-analytics-output-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Create Kinesis stream
    log_step "Creating Kinesis stream..."
    aws kinesis create-stream --stream-name "${name}-input" --shard-count 1 2>/dev/null || log_info "Stream exists"
    log_info "Waiting for stream..."
    aws kinesis wait stream-exists --stream-name "${name}-input"

    local stream_arn=$(aws kinesis describe-stream --stream-name "${name}-input" --query 'StreamDescription.StreamARN' --output text)

    # Create IAM role
    log_step "Creating IAM role..."
    local role_name="${name}-kda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"kinesisanalytics.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["kinesis:DescribeStream","kinesis:GetShardIterator","kinesis:GetRecords","kinesis:ListShards"],
            "Resource": "$stream_arn"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": ["arn:aws:s3:::$bucket_name","arn:aws:s3:::$bucket_name/*"]
        },
        {
            "Effect": "Allow",
            "Action": ["logs:*"],
            "Resource": "arn:aws:logs:$DEFAULT_REGION:$account_id:*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-policy" --policy-document "$policy"

    sleep 10

    # Create Analytics application
    log_step "Creating Kinesis Analytics application..."
    aws kinesisanalytics create-application \
        --application-name "${name}-app" \
        --application-description "Stream analytics" \
        --inputs "[{
            \"NamePrefix\": \"SOURCE_SQL_STREAM\",
            \"KinesisStreamsInput\": {
                \"ResourceARN\": \"$stream_arn\",
                \"RoleARN\": \"arn:aws:iam::$account_id:role/$role_name\"
            },
            \"InputSchema\": {
                \"RecordFormat\": {\"RecordFormatType\": \"JSON\", \"MappingParameters\": {\"JSONMappingParameters\": {\"RecordRowPath\": \"\$\"}}},
                \"RecordColumns\": [
                    {\"Name\": \"timestamp\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.timestamp\"},
                    {\"Name\": \"sensor_type\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.sensor_type\"},
                    {\"Name\": \"device_id\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.device_id\"},
                    {\"Name\": \"value\", \"SqlType\": \"DOUBLE\", \"Mapping\": \"\$.value\"},
                    {\"Name\": \"location\", \"SqlType\": \"VARCHAR(32)\", \"Mapping\": \"\$.location\"}
                ]
            }
        }]" \
        --application-code "
CREATE OR REPLACE STREAM \"DESTINATION_SQL_STREAM\" (sensor_type VARCHAR(32), location VARCHAR(32), avg_value DOUBLE, record_count INTEGER);
CREATE OR REPLACE PUMP \"STREAM_PUMP\" AS INSERT INTO \"DESTINATION_SQL_STREAM\"
SELECT STREAM sensor_type, location, AVG(value) AS avg_value, COUNT(*) AS record_count
FROM \"SOURCE_SQL_STREAM_001\"
GROUP BY sensor_type, location, STEP(\"SOURCE_SQL_STREAM_001\".ROWTIME BY INTERVAL '60' SECOND);
" 2>/dev/null || log_info "Application exists"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Kinesis Stream: ${name}-input"
    echo "Analytics Application: ${name}-app"
    echo "Output Bucket: $bucket_name"
    echo ""
    echo "Generate test data:"
    echo "  $0 generate-data ${name}-input 100"
    echo ""
    echo "Start the analytics application:"
    echo "  $0 app-start ${name}-app"
    echo ""
    echo "Check application status:"
    echo "  $0 app-describe ${name}-app"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Stop and delete Analytics application
    aws kinesisanalytics stop-application --application-name "${name}-app" 2>/dev/null || true
    sleep 5
    local create_timestamp=$(aws kinesisanalytics describe-application --application-name "${name}-app" --query 'ApplicationDetail.CreateTimestamp' --output text 2>/dev/null)
    if [ -n "$create_timestamp" ] && [ "$create_timestamp" != "None" ]; then
        aws kinesisanalytics delete-application --application-name "${name}-app" --create-timestamp "$create_timestamp" 2>/dev/null || true
    fi

    # Delete Kinesis stream
    aws kinesis delete-stream --stream-name "${name}-input" 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-analytics-output-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM role
    aws iam delete-role-policy --role-name "${name}-kda-role" --policy-name "${name}-policy" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-kda-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Kinesis Streams ===${NC}"
    stream_list
    echo -e "\n${BLUE}=== Analytics Applications ===${NC}"
    app_list
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    bucket_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    stream-create) stream_create "$@" ;;
    stream-delete) stream_delete "$@" ;;
    stream-list) stream_list ;;
    put-record) put_record "$@" ;;
    generate-data) generate_data "$@" ;;
    app-create) app_create "$@" ;;
    app-delete) app_delete "$@" ;;
    app-list) app_list ;;
    app-describe) app_describe "$@" ;;
    app-start) app_start "$@" ;;
    app-stop) app_stop "$@" ;;
    app-update) app_update "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    output-list) output_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
