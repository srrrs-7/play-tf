#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# MSK → Lambda → DynamoDB Architecture Script
# Provides operations for Kafka-based stream processing

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "MSK → Lambda → DynamoDB Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy Kafka processing stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "MSK (Amazon Managed Streaming for Apache Kafka):"
    echo "  cluster-create <name>                - Create MSK Serverless cluster"
    echo "  cluster-delete <arn>                 - Delete MSK cluster"
    echo "  cluster-list                         - List MSK clusters"
    echo "  cluster-describe <arn>               - Describe cluster"
    echo "  get-bootstrap <arn>                  - Get bootstrap servers"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-add-trigger <func> <cluster-arn> <topic> - Add MSK trigger"
    echo ""
    echo "DynamoDB:"
    echo "  table-create <name> <pk>             - Create table"
    echo "  table-delete <name>                  - Delete table"
    echo "  table-list                           - List tables"
    echo "  item-scan <table>                    - Scan table"
    echo ""
    echo "VPC:"
    echo "  vpc-create <name>                    - Create VPC for MSK"
    echo "  vpc-delete <vpc-id>                  - Delete VPC"
    echo ""
    exit 1
}

# VPC Functions
vpc_create() {
    local name=$1
    [ -z "$name" ] && { log_error "VPC name required"; exit 1; }

    log_step "Creating VPC: $name"

    local vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
    aws ec2 create-tags --resources "$vpc_id" --tags "Key=Name,Value=$name"
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames

    local azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:3].ZoneName' --output text)
    local az_array=($azs)

    local subnet_ids=""
    for i in 0 1 2; do
        local az=${az_array[$i]}
        local cidr="10.0.$((i+1)).0/24"
        local subnet_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "$cidr" --availability-zone "$az" --query 'Subnet.SubnetId' --output text)
        aws ec2 create-tags --resources "$subnet_id" --tags "Key=Name,Value=${name}-subnet-$((i+1))"
        subnet_ids="$subnet_ids $subnet_id"
    done

    local sg_id=$(aws ec2 create-security-group --group-name "${name}-msk-sg" --description "Security group for MSK" --vpc-id "$vpc_id" --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 9092 --source-group "$sg_id"
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 9094 --source-group "$sg_id"
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 2181 --source-group "$sg_id"

    log_info "VPC created: $vpc_id"
    echo "VPC_ID=$vpc_id"
    echo "SUBNETS=$subnet_ids"
    echo "SECURITY_GROUP=$sg_id"
}

vpc_delete() {
    local vpc_id=$1
    [ -z "$vpc_id" ] && { log_error "VPC ID required"; exit 1; }

    log_warn "Deleting VPC: $vpc_id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text); do
        aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
    done

    for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_info "VPC deleted"
}

# MSK Functions
cluster_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Cluster name required"; exit 1; }

    log_step "Creating MSK Serverless cluster: $name"
    log_warn "MSK Serverless cluster creation requires VPC. Use 'deploy' for full stack setup."

    # This is a simplified version - full deployment in deploy()
    log_info "Use 'deploy <name>' to create full MSK stack with VPC"
}

cluster_delete() {
    local arn=$1
    aws kafka delete-cluster --cluster-arn "$arn"
    log_info "Cluster deletion initiated"
}

cluster_list() {
    aws kafka list-clusters-v2 --query 'ClusterInfoList[].{Name:ClusterName,Arn:ClusterArn,Type:ClusterType,State:State}' --output table 2>/dev/null || \
    aws kafka list-clusters --query 'ClusterInfoList[].{Name:ClusterName,Arn:ClusterArn,State:State}' --output table
}

cluster_describe() {
    local arn=$1
    aws kafka describe-cluster-v2 --cluster-arn "$arn" --output json 2>/dev/null || \
    aws kafka describe-cluster --cluster-arn "$arn" --output json
}

get_bootstrap() {
    local arn=$1
    aws kafka get-bootstrap-brokers --cluster-arn "$arn" --query 'BootstrapBrokerString' --output text 2>/dev/null || \
    aws kafka get-bootstrap-brokers --cluster-arn "$arn" --query 'BootstrapBrokerStringSaslIam' --output text
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Name and zip file required"
        exit 1
    fi

    log_step "Creating Lambda: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 60 \
        --memory-size 256

    log_info "Lambda created"
}

lambda_delete() {
    local name=$1
    aws lambda delete-function --function-name "$name"
    log_info "Lambda deleted"
}

lambda_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' --output table
}

lambda_add_trigger() {
    local func=$1
    local cluster_arn=$2
    local topic=$3

    if [ -z "$func" ] || [ -z "$cluster_arn" ] || [ -z "$topic" ]; then
        log_error "Function name, cluster ARN, and topic required"
        exit 1
    fi

    aws lambda create-event-source-mapping \
        --function-name "$func" \
        --event-source-arn "$cluster_arn" \
        --topics "$topic" \
        --starting-position LATEST \
        --batch-size 100

    log_info "MSK trigger added"
}

# DynamoDB Functions
table_create() {
    local name=$1
    local pk=$2

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key required"
        exit 1
    fi

    log_step "Creating table: $name"
    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}]" \
        --key-schema "[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}]" \
        --billing-mode PAY_PER_REQUEST

    aws dynamodb wait table-exists --table-name "$name"
    log_info "Table created"
}

table_delete() {
    local name=$1
    log_warn "Deleting table: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws dynamodb delete-table --table-name "$name"
    log_info "Table deleted"
}

table_list() {
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

item_scan() {
    local table=$1
    aws dynamodb scan --table-name "$table" --output json
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying MSK → Lambda → DynamoDB stack: $name"
    local account_id=$(get_account_id)

    # Create VPC
    log_step "Creating VPC..."
    local vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
    aws ec2 create-tags --resources "$vpc_id" --tags "Key=Name,Value=$name"
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames

    local azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az_array=($azs)

    local subnet1=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.1.0/24 --availability-zone "${az_array[0]}" --query 'Subnet.SubnetId' --output text)
    local subnet2=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.2.0/24 --availability-zone "${az_array[1]}" --query 'Subnet.SubnetId' --output text)

    aws ec2 create-tags --resources "$subnet1" --tags "Key=Name,Value=${name}-subnet-1"
    aws ec2 create-tags --resources "$subnet2" --tags "Key=Name,Value=${name}-subnet-2"

    local sg_id=$(aws ec2 create-security-group --group-name "${name}-sg" --description "Security group for $name" --vpc-id "$vpc_id" --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol -1 --source-group "$sg_id"

    # Create DynamoDB table
    log_step "Creating DynamoDB table..."
    aws dynamodb create-table \
        --table-name "${name}-events" \
        --attribute-definitions '[{"AttributeName":"eventId","AttributeType":"S"}]' \
        --key-schema '[{"AttributeName":"eventId","KeyType":"HASH"}]' \
        --billing-mode PAY_PER_REQUEST 2>/dev/null || log_info "Table already exists"

    aws dynamodb wait table-exists --table-name "${name}-events"

    # Create MSK Serverless cluster
    log_step "Creating MSK Serverless cluster..."
    local serverless_config=$(cat << EOF
{
    "VpcConfigs": [{
        "SubnetIds": ["$subnet1", "$subnet2"],
        "SecurityGroupIds": ["$sg_id"]
    }],
    "ClientAuthentication": {
        "Sasl": {
            "Iam": {
                "Enabled": true
            }
        }
    }
}
EOF
)

    local cluster_arn=$(aws kafka create-cluster-v2 \
        --cluster-name "$name" \
        --serverless "$serverless_config" \
        --query 'ClusterArn' --output text 2>/dev/null) || {
        log_warn "MSK Serverless not available or cluster exists. Using existing or creating provisioned cluster."
        # Alternative: Create provisioned cluster
        cluster_arn=$(aws kafka list-clusters --cluster-name-filter "$name" --query 'ClusterInfoList[0].ClusterArn' --output text)
    }

    if [ -n "$cluster_arn" ] && [ "$cluster_arn" != "None" ]; then
        log_info "Waiting for MSK cluster to become active..."
        local cluster_state="CREATING"
        local max_wait=60
        local wait_count=0
        while [ "$cluster_state" != "ACTIVE" ] && [ $wait_count -lt $max_wait ]; do
            sleep 30
            cluster_state=$(aws kafka describe-cluster-v2 --cluster-arn "$cluster_arn" --query 'ClusterInfo.State' --output text 2>/dev/null || echo "CREATING")
            wait_count=$((wait_count + 1))
            log_info "Cluster state: $cluster_state (waiting $((wait_count * 30))s)"
        done
    fi

    # Create Lambda
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const TABLE = process.env.TABLE_NAME;

exports.handler = async (event) => {
    console.log('Processing MSK event:', JSON.stringify(event));

    const results = [];
    for (const [topic, partitions] of Object.entries(event.records || {})) {
        for (const record of partitions) {
            try {
                // Decode base64 value
                const value = Buffer.from(record.value, 'base64').toString('utf-8');
                let data;
                try {
                    data = JSON.parse(value);
                } catch {
                    data = { raw: value };
                }

                const item = {
                    eventId: `${topic}-${record.partition}-${record.offset}`,
                    topic: topic,
                    partition: record.partition,
                    offset: record.offset,
                    timestamp: record.timestamp,
                    data: data,
                    processedAt: new Date().toISOString()
                };

                await docClient.send(new PutCommand({
                    TableName: TABLE,
                    Item: item
                }));

                results.push({ topic, partition: record.partition, offset: record.offset, status: 'success' });
                console.log('Processed record:', item.eventId);
            } catch (error) {
                console.error('Error processing record:', error);
                throw error;
            }
        }
    }

    return {
        statusCode: 200,
        recordsProcessed: results.length
    };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 60 \
        --vpc-config "SubnetIds=$subnet1,$subnet2,SecurityGroupIds=$sg_id" \
        --environment "Variables={TABLE_NAME=${name}-events}" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    # Add MSK trigger (if cluster is ready)
    if [ -n "$cluster_arn" ] && [ "$cluster_arn" != "None" ]; then
        log_step "Adding MSK trigger..."
        aws lambda create-event-source-mapping \
            --function-name "${name}-processor" \
            --event-source-arn "$cluster_arn" \
            --topics "events" \
            --starting-position LATEST \
            --batch-size 100 2>/dev/null || log_warn "MSK trigger creation deferred - cluster may not be ready"
    fi

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "VPC ID: $vpc_id"
    echo "MSK Cluster: $cluster_arn"
    echo "DynamoDB Table: ${name}-events"
    echo "Lambda: ${name}-processor"
    echo ""
    echo -e "${YELLOW}Note: MSK Serverless cluster may take 15-30 minutes to become active.${NC}"
    echo ""
    echo "To produce messages to Kafka, use kafka-console-producer or your Kafka client:"
    echo "  1. Get bootstrap servers: aws kafka get-bootstrap-brokers --cluster-arn '$cluster_arn'"
    echo "  2. Connect using SASL/IAM authentication"
    echo ""
    echo "Check DynamoDB for processed events:"
    echo "  aws dynamodb scan --table-name '${name}-events'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete event source mapping
    local esm_uuid=$(aws lambda list-event-source-mappings --function-name "${name}-processor" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm_uuid" ] && [ "$esm_uuid" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm_uuid"

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete MSK cluster
    local cluster_arn=$(aws kafka list-clusters-v2 --cluster-name-filter "$name" --query 'ClusterInfoList[0].ClusterArn' --output text 2>/dev/null)
    [ -n "$cluster_arn" ] && [ "$cluster_arn" != "None" ] && aws kafka delete-cluster --cluster-arn "$cluster_arn"

    # Delete DynamoDB
    aws dynamodb delete-table --table-name "${name}-events" 2>/dev/null || true

    # Find and delete VPC
    local vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$name" --query 'Vpcs[0].VpcId' --output text)
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text); do
            aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
        done
        for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
            aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
        done
        aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || true
    fi

    # Delete IAM role
    for policy in AWSLambdaBasicExecutionRole AWSLambdaMSKExecutionRole AWSLambdaVPCAccessExecutionRole; do
        aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn "arn:aws:iam::aws:policy/service-role/$policy" 2>/dev/null || true
    done
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== MSK Clusters ===${NC}"
    cluster_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== DynamoDB Tables ===${NC}"
    table_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    cluster-create) cluster_create "$@" ;;
    cluster-delete) cluster_delete "$@" ;;
    cluster-list) cluster_list ;;
    cluster-describe) cluster_describe "$@" ;;
    get-bootstrap) get_bootstrap "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-add-trigger) lambda_add_trigger "$@" ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    table-list) table_list ;;
    item-scan) item_scan "$@" ;;
    vpc-create) vpc_create "$@" ;;
    vpc-delete) vpc_delete "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
