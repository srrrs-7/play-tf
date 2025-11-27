#!/bin/bash

set -e

# IoT Core → Kinesis Data Streams → Lambda Architecture Script
# Provides operations for IoT data ingestion and processing

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "IoT Core → Kinesis Data Streams → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy IoT processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "IoT Core:"
    echo "  thing-create <name>                        - Create IoT thing"
    echo "  thing-delete <name>                        - Delete thing"
    echo "  thing-list                                 - List things"
    echo "  policy-create <name>                       - Create IoT policy"
    echo "  rule-create <name> <sql> <stream>          - Create IoT rule to Kinesis"
    echo "  rule-delete <name>                         - Delete rule"
    echo "  rule-list                                  - List rules"
    echo "  cert-create <thing>                        - Create and attach certificate"
    echo "  publish <topic> <payload>                  - Publish MQTT message"
    echo ""
    echo "Kinesis:"
    echo "  stream-create <name> [shards]              - Create data stream"
    echo "  stream-delete <name>                       - Delete stream"
    echo "  stream-list                                - List streams"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>            - Create function"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo "  trigger-add <function> <stream-arn>        - Add Kinesis trigger"
    echo ""
    exit 1
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_aws_cli() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured"
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

# IoT Functions
thing_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Thing name required"; exit 1; }

    aws iot create-thing --thing-name "$name"
    log_info "Thing created: $name"
}

thing_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Thing name required"; exit 1; }

    # Detach principals first
    local principals=$(aws iot list-thing-principals --thing-name "$name" --query 'principals[]' --output text 2>/dev/null)
    for p in $principals; do
        aws iot detach-thing-principal --thing-name "$name" --principal "$p"
    done

    aws iot delete-thing --thing-name "$name"
    log_info "Thing deleted"
}

thing_list() {
    aws iot list-things --query 'things[].{Name:thingName,TypeName:thingTypeName}' --output table
}

policy_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Policy name required"; exit 1; }

    local account_id=$(get_account_id)

    local policy_doc=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["iot:Connect"],
            "Resource": "arn:aws:iot:$DEFAULT_REGION:$account_id:client/*"
        },
        {
            "Effect": "Allow",
            "Action": ["iot:Publish", "iot:Receive"],
            "Resource": "arn:aws:iot:$DEFAULT_REGION:$account_id:topic/*"
        },
        {
            "Effect": "Allow",
            "Action": ["iot:Subscribe"],
            "Resource": "arn:aws:iot:$DEFAULT_REGION:$account_id:topicfilter/*"
        }
    ]
}
EOF
)

    aws iot create-policy --policy-name "$name" --policy-document "$policy_doc"
    log_info "Policy created: $name"
}

rule_create() {
    local name=$1
    local sql=$2
    local stream=$3

    if [ -z "$name" ] || [ -z "$sql" ] || [ -z "$stream" ]; then
        log_error "Rule name, SQL statement, and Kinesis stream required"
        exit 1
    fi

    local account_id=$(get_account_id)

    # Create role for IoT to write to Kinesis
    local role_name="${name}-iot-kinesis-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"iot.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["kinesis:PutRecord", "kinesis:PutRecords"],
        "Resource": "arn:aws:kinesis:$DEFAULT_REGION:$account_id:stream/$stream"
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-kinesis" --policy-document "$policy"

    sleep 10

    aws iot create-topic-rule \
        --rule-name "$name" \
        --topic-rule-payload "{
            \"sql\": \"$sql\",
            \"actions\": [{
                \"kinesis\": {
                    \"streamName\": \"$stream\",
                    \"roleArn\": \"arn:aws:iam::$account_id:role/$role_name\",
                    \"partitionKey\": \"\${newuuid()}\"
                }
            }]
        }"

    log_info "Rule created: $name"
}

rule_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Rule name required"; exit 1; }
    aws iot delete-topic-rule --rule-name "$name"
    log_info "Rule deleted"
}

rule_list() {
    aws iot list-topic-rules --query 'rules[].{Name:ruleName,Disabled:ruleDisabled}' --output table
}

cert_create() {
    local thing=$1
    [ -z "$thing" ] && { log_error "Thing name required"; exit 1; }

    local result=$(aws iot create-keys-and-certificate --set-as-active --output json)
    local cert_arn=$(echo "$result" | jq -r '.certificateArn')
    local cert_id=$(echo "$result" | jq -r '.certificateId')

    echo "$result" | jq -r '.certificatePem' > "/tmp/${thing}-cert.pem"
    echo "$result" | jq -r '.keyPair.PrivateKey' > "/tmp/${thing}-private.key"
    echo "$result" | jq -r '.keyPair.PublicKey' > "/tmp/${thing}-public.key"

    aws iot attach-thing-principal --thing-name "$thing" --principal "$cert_arn"

    log_info "Certificate created and attached"
    echo "Certificate files saved to /tmp/${thing}-*.pem/key"
    echo "Certificate ARN: $cert_arn"
}

publish() {
    local topic=$1
    local payload=$2

    if [ -z "$topic" ] || [ -z "$payload" ]; then
        log_error "Topic and payload required"
        exit 1
    fi

    aws iot-data publish --topic "$topic" --payload "$payload" --cli-binary-format raw-in-base64-out
    log_info "Message published to $topic"
}

# Kinesis Functions
stream_create() {
    local name=$1
    local shards=${2:-1}

    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }

    aws kinesis create-stream --stream-name "$name" --shard-count "$shards"
    aws kinesis wait stream-exists --stream-name "$name"
    log_info "Stream created: $name"
}

stream_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }
    aws kinesis delete-stream --stream-name "$name"
    log_info "Stream deleted"
}

stream_list() {
    aws kinesis list-streams --query 'StreamNames[]' --output table
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Name and zip file required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 60

    log_info "Lambda created"
}

lambda_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Function name required"; exit 1; }
    aws lambda delete-function --function-name "$name"
    log_info "Lambda deleted"
}

lambda_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' --output table
}

trigger_add() {
    local func=$1
    local stream_arn=$2

    if [ -z "$func" ] || [ -z "$stream_arn" ]; then
        log_error "Function name and stream ARN required"
        exit 1
    fi

    aws lambda create-event-source-mapping \
        --function-name "$func" \
        --event-source-arn "$stream_arn" \
        --batch-size 100 \
        --starting-position LATEST

    log_info "Trigger added"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying IoT Core → Kinesis → Lambda stack: $name"
    local account_id=$(get_account_id)

    # Create Kinesis stream
    log_step "Creating Kinesis stream..."
    aws kinesis create-stream --stream-name "${name}-stream" --shard-count 1 2>/dev/null || log_info "Stream exists"
    aws kinesis wait stream-exists --stream-name "${name}-stream"
    local stream_arn=$(aws kinesis describe-stream --stream-name "${name}-stream" --query 'StreamDescription.StreamARN' --output text)

    # Create Lambda processor
    log_step "Creating Lambda processor..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
exports.handler = async (event) => {
    console.log(`Processing ${event.Records.length} IoT records from Kinesis`);

    for (const record of event.Records) {
        const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');

        let data;
        try {
            data = JSON.parse(payload);
        } catch {
            data = { raw: payload };
        }

        console.log('IoT Data:', {
            sequenceNumber: record.kinesis.sequenceNumber,
            partitionKey: record.kinesis.partitionKey,
            timestamp: record.kinesis.approximateArrivalTimestamp,
            data: data
        });

        // Process IoT data here
        // Examples: store in DynamoDB, trigger alerts, update dashboards
        if (data.temperature && data.temperature > 30) {
            console.log('HIGH TEMPERATURE ALERT:', data.deviceId, data.temperature);
        }
    }

    return { statusCode: 200, processed: event.Records.length };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 60 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    # Add Kinesis trigger
    aws lambda create-event-source-mapping \
        --function-name "${name}-processor" \
        --event-source-arn "$stream_arn" \
        --batch-size 100 \
        --starting-position LATEST 2>/dev/null || true

    # Create IoT rule
    log_step "Creating IoT rule..."
    local iot_role="${name}-iot-kinesis-role"
    local iot_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"iot.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$iot_role" --assume-role-policy-document "$iot_trust" 2>/dev/null || true

    local iot_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["kinesis:PutRecord","kinesis:PutRecords"],"Resource":"$stream_arn"}]}
EOF
)
    aws iam put-role-policy --role-name "$iot_role" --policy-name "${name}-kinesis" --policy-document "$iot_policy"

    sleep 10

    aws iot create-topic-rule \
        --rule-name "${name}_rule" \
        --topic-rule-payload "{
            \"sql\": \"SELECT * FROM 'devices/+/telemetry'\",
            \"actions\": [{
                \"kinesis\": {
                    \"streamName\": \"${name}-stream\",
                    \"roleArn\": \"arn:aws:iam::$account_id:role/$iot_role\",
                    \"partitionKey\": \"\${topic(2)}\"
                }
            }]
        }" 2>/dev/null || log_info "Rule exists"

    # Create IoT policy
    log_step "Creating IoT policy..."
    local policy_doc=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {"Effect": "Allow", "Action": ["iot:Connect"], "Resource": "arn:aws:iot:$DEFAULT_REGION:$account_id:client/*"},
        {"Effect": "Allow", "Action": ["iot:Publish"], "Resource": "arn:aws:iot:$DEFAULT_REGION:$account_id:topic/devices/*/telemetry"}
    ]
}
EOF
)
    aws iot create-policy --policy-name "${name}-policy" --policy-document "$policy_doc" 2>/dev/null || true

    rm -rf "$lambda_dir"

    local endpoint=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query 'endpointAddress' --output text)

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Kinesis Stream: ${name}-stream"
    echo "Lambda Processor: ${name}-processor"
    echo "IoT Rule: ${name}_rule"
    echo "IoT Policy: ${name}-policy"
    echo "IoT Endpoint: $endpoint"
    echo ""
    echo "Test by publishing IoT message:"
    echo "  aws iot-data publish --topic 'devices/sensor1/telemetry' \\"
    echo "    --payload '{\"deviceId\":\"sensor1\",\"temperature\":25.5,\"humidity\":60}' \\"
    echo "    --cli-binary-format raw-in-base64-out"
    echo ""
    echo "View Lambda logs:"
    echo "  aws logs tail /aws/lambda/${name}-processor --follow"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete IoT resources
    aws iot delete-topic-rule --rule-name "${name}_rule" 2>/dev/null || true
    aws iot delete-policy --policy-name "${name}-policy" 2>/dev/null || true

    # Delete Lambda
    local esm=$(aws lambda list-event-source-mappings --function-name "${name}-processor" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm" ] && [ "$esm" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm" 2>/dev/null || true
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete Kinesis stream
    aws kinesis delete-stream --stream-name "${name}-stream" 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-iot-kinesis-role" --policy-name "${name}-kinesis" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-iot-kinesis-role" 2>/dev/null || true

    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== IoT Things ===${NC}"
    thing_list
    echo -e "\n${BLUE}=== IoT Rules ===${NC}"
    rule_list
    echo -e "\n${BLUE}=== Kinesis Streams ===${NC}"
    stream_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    thing-create) thing_create "$@" ;;
    thing-delete) thing_delete "$@" ;;
    thing-list) thing_list ;;
    policy-create) policy_create "$@" ;;
    rule-create) rule_create "$@" ;;
    rule-delete) rule_delete "$@" ;;
    rule-list) rule_list ;;
    cert-create) cert_create "$@" ;;
    publish) publish "$@" ;;
    stream-create) stream_create "$@" ;;
    stream-delete) stream_delete "$@" ;;
    stream-list) stream_list ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    trigger-add) trigger_add "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
