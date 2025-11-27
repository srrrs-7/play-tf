#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# AppSync → Lambda → Aurora Architecture Script
# Provides operations for GraphQL API with Lambda resolvers and Aurora Serverless

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "AppSync → Lambda → Aurora Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full GraphQL API stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "AppSync:"
    echo "  api-create <name>                    - Create GraphQL API"
    echo "  api-delete <api-id>                  - Delete GraphQL API"
    echo "  api-list                             - List GraphQL APIs"
    echo "  api-get-url <api-id>                 - Get API URL"
    echo "  schema-update <api-id> <schema-file> - Update schema"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-update <name> <zip-file>      - Update code"
    echo ""
    echo "Aurora:"
    echo "  cluster-create <name>                - Create Aurora Serverless cluster"
    echo "  cluster-delete <name>                - Delete cluster"
    echo "  cluster-list                         - List clusters"
    echo "  cluster-start <name>                 - Start cluster"
    echo "  cluster-stop <name>                  - Stop cluster"
    echo "  db-create <cluster> <db-name>        - Create database"
    echo "  query <cluster> <sql>                - Execute SQL query"
    echo ""
    echo "VPC:"
    echo "  vpc-create <name>                    - Create VPC for Aurora"
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

    # Create subnets (at least 2 AZs required for Aurora)
    local azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az1=$(echo $azs | awk '{print $1}')
    local az2=$(echo $azs | awk '{print $2}')

    local subnet1=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.1.0/24 --availability-zone "$az1" --query 'Subnet.SubnetId' --output text)
    local subnet2=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.2.0/24 --availability-zone "$az2" --query 'Subnet.SubnetId' --output text)

    aws ec2 create-tags --resources "$subnet1" --tags "Key=Name,Value=${name}-subnet-1"
    aws ec2 create-tags --resources "$subnet2" --tags "Key=Name,Value=${name}-subnet-2"

    # Create security group
    local sg_id=$(aws ec2 create-security-group --group-name "${name}-sg" --description "Security group for $name" --vpc-id "$vpc_id" --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 3306 --source-group "$sg_id"

    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${name}-subnet-group" \
        --db-subnet-group-description "Subnet group for $name" \
        --subnet-ids "$subnet1" "$subnet2"

    log_info "VPC created: $vpc_id"
    echo "VPC_ID=$vpc_id"
    echo "SUBNET_1=$subnet1"
    echo "SUBNET_2=$subnet2"
    echo "SECURITY_GROUP=$sg_id"
}

vpc_delete() {
    local vpc_id=$1
    [ -z "$vpc_id" ] && { log_error "VPC ID required"; exit 1; }

    log_warn "Deleting VPC: $vpc_id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Delete subnets
    for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text); do
        aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
    done

    # Delete security groups (except default)
    for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_info "VPC deleted"
}

# Aurora Functions
cluster_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Cluster name required"; exit 1; }

    log_step "Creating Aurora Serverless cluster: $name"

    local account_id=$(get_account_id)

    aws rds create-db-cluster \
        --db-cluster-identifier "$name" \
        --engine aurora-mysql \
        --engine-version 8.0.mysql_aurora.3.04.0 \
        --engine-mode provisioned \
        --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=4 \
        --master-username admin \
        --master-user-password "$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)Aa1!" \
        --db-subnet-group-name "${name}-subnet-group" \
        --enable-http-endpoint

    # Create instance
    aws rds create-db-instance \
        --db-instance-identifier "${name}-instance" \
        --db-cluster-identifier "$name" \
        --engine aurora-mysql \
        --db-instance-class db.serverless

    log_info "Aurora cluster creation initiated"
    log_info "Wait for cluster to be available before using"
}

cluster_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Cluster name required"; exit 1; }

    log_warn "Deleting Aurora cluster: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws rds delete-db-instance --db-instance-identifier "${name}-instance" --skip-final-snapshot 2>/dev/null || true
    aws rds wait db-instance-deleted --db-instance-identifier "${name}-instance" 2>/dev/null || true
    aws rds delete-db-cluster --db-cluster-identifier "$name" --skip-final-snapshot
    log_info "Cluster deleted"
}

cluster_list() {
    aws rds describe-db-clusters --query 'DBClusters[].{Name:DBClusterIdentifier,Status:Status,Engine:Engine}' --output table
}

cluster_start() {
    local name=$1
    aws rds start-db-cluster --db-cluster-identifier "$name"
    log_info "Cluster starting"
}

cluster_stop() {
    local name=$1
    aws rds stop-db-cluster --db-cluster-identifier "$name"
    log_info "Cluster stopping"
}

db_query() {
    local cluster=$1
    local sql=$2

    local arn=$(aws rds describe-db-clusters --db-cluster-identifier "$cluster" --query 'DBClusters[0].DBClusterArn' --output text)
    local secret_arn=$(aws rds describe-db-clusters --db-cluster-identifier "$cluster" --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text)

    aws rds-data execute-statement \
        --resource-arn "$arn" \
        --secret-arn "$secret_arn" \
        --sql "$sql" \
        --output json
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
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonRDSDataFullAccess 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 30 \
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

lambda_update() {
    local name=$1
    local zip_file=$2
    aws lambda update-function-code --function-name "$name" --zip-file "fileb://$zip_file"
    log_info "Lambda updated"
}

# AppSync Functions
api_create() {
    local name=$1

    log_step "Creating GraphQL API: $name"
    local api_id=$(aws appsync create-graphql-api \
        --name "$name" \
        --authentication-type API_KEY \
        --query 'graphqlApi.apiId' --output text)

    local expires=$(python3 -c "import time; print(int(time.time()) + 365*24*60*60)")
    aws appsync create-api-key --api-id "$api_id" --expires "$expires" > /dev/null

    log_info "API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local api_id=$1
    aws appsync delete-graphql-api --api-id "$api_id"
    log_info "API deleted"
}

api_list() {
    aws appsync list-graphql-apis --query 'graphqlApis[].{Name:name,Id:apiId,Endpoint:uris.GRAPHQL}' --output table
}

api_get_url() {
    local api_id=$1
    aws appsync get-graphql-api --api-id "$api_id" --query 'graphqlApi.uris.GRAPHQL' --output text
}

schema_update() {
    local api_id=$1
    local schema_file=$2

    log_step "Updating schema..."
    local schema=$(base64 < "$schema_file" | tr -d '\n')
    aws appsync start-schema-creation --api-id "$api_id" --definition "$schema"

    local status="PROCESSING"
    while [ "$status" == "PROCESSING" ]; do
        sleep 2
        status=$(aws appsync get-schema-creation-status --api-id "$api_id" --query 'status' --output text)
    done

    if [ "$status" == "SUCCESS" ]; then
        log_info "Schema updated"
    else
        log_error "Schema update failed: $status"
        exit 1
    fi
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying AppSync → Lambda → Aurora stack: $name"
    local account_id=$(get_account_id)

    # Create VPC
    log_step "Creating VPC..."
    local vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
    aws ec2 create-tags --resources "$vpc_id" --tags "Key=Name,Value=$name"
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames

    local azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az1=$(echo $azs | awk '{print $1}')
    local az2=$(echo $azs | awk '{print $2}')

    local subnet1=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.1.0/24 --availability-zone "$az1" --query 'Subnet.SubnetId' --output text)
    local subnet2=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.2.0/24 --availability-zone "$az2" --query 'Subnet.SubnetId' --output text)

    aws ec2 create-tags --resources "$subnet1" --tags "Key=Name,Value=${name}-subnet-1"
    aws ec2 create-tags --resources "$subnet2" --tags "Key=Name,Value=${name}-subnet-2"

    local sg_id=$(aws ec2 create-security-group --group-name "${name}-sg" --description "Security group for $name" --vpc-id "$vpc_id" --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 3306 --source-group "$sg_id"
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 443 --cidr 0.0.0.0/0

    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${name}-subnet-group" \
        --db-subnet-group-description "Subnet group for $name" \
        --subnet-ids "$subnet1" "$subnet2"

    # Create Aurora cluster
    log_step "Creating Aurora Serverless cluster..."
    local db_password="$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')Aa1!"

    aws rds create-db-cluster \
        --db-cluster-identifier "$name" \
        --engine aurora-mysql \
        --engine-version 8.0.mysql_aurora.3.04.0 \
        --engine-mode provisioned \
        --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=4 \
        --master-username admin \
        --master-user-password "$db_password" \
        --db-subnet-group-name "${name}-subnet-group" \
        --vpc-security-group-ids "$sg_id" \
        --enable-http-endpoint \
        --manage-master-user-password

    aws rds create-db-instance \
        --db-instance-identifier "${name}-instance" \
        --db-cluster-identifier "$name" \
        --engine aurora-mysql \
        --db-instance-class db.serverless

    log_info "Waiting for Aurora cluster to be available..."
    aws rds wait db-cluster-available --db-cluster-identifier "$name"

    local cluster_arn=$(aws rds describe-db-clusters --db-cluster-identifier "$name" --query 'DBClusters[0].DBClusterArn' --output text)
    local secret_arn=$(aws rds describe-db-clusters --db-cluster-identifier "$name" --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text)

    # Create Lambda
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'LAMBDAEOF' > "$lambda_dir/index.js"
const { RDSDataClient, ExecuteStatementCommand } = require('@aws-sdk/client-rds-data');

const client = new RDSDataClient({});
const CLUSTER_ARN = process.env.CLUSTER_ARN;
const SECRET_ARN = process.env.SECRET_ARN;
const DATABASE = process.env.DATABASE || 'mydb';

const executeSQL = async (sql, parameters = []) => {
    const command = new ExecuteStatementCommand({
        resourceArn: CLUSTER_ARN,
        secretArn: SECRET_ARN,
        database: DATABASE,
        sql,
        parameters
    });
    return await client.send(command);
};

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event));
    const { field, arguments: args } = event;

    try {
        switch (field) {
            case 'listUsers':
                const users = await executeSQL('SELECT * FROM users');
                return users.records?.map(r => ({
                    id: r[0]?.stringValue,
                    name: r[1]?.stringValue,
                    email: r[2]?.stringValue
                })) || [];

            case 'getUser':
                const user = await executeSQL(
                    'SELECT * FROM users WHERE id = :id',
                    [{ name: 'id', value: { stringValue: args.id } }]
                );
                if (user.records?.length > 0) {
                    return {
                        id: user.records[0][0]?.stringValue,
                        name: user.records[0][1]?.stringValue,
                        email: user.records[0][2]?.stringValue
                    };
                }
                return null;

            case 'createUser':
                const id = require('crypto').randomUUID();
                await executeSQL(
                    'INSERT INTO users (id, name, email) VALUES (:id, :name, :email)',
                    [
                        { name: 'id', value: { stringValue: id } },
                        { name: 'name', value: { stringValue: args.input.name } },
                        { name: 'email', value: { stringValue: args.input.email } }
                    ]
                );
                return { id, name: args.input.name, email: args.input.email };

            case 'deleteUser':
                await executeSQL(
                    'DELETE FROM users WHERE id = :id',
                    [{ name: 'id', value: { stringValue: args.id } }]
                );
                return { id: args.id };

            default:
                throw new Error(`Unknown field: ${field}`);
        }
    } catch (error) {
        console.error('Error:', error);
        throw error;
    }
};
LAMBDAEOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-lambda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonRDSDataFullAccess 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "${name}-resolver" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 30 \
        --memory-size 256 \
        --environment "Variables={CLUSTER_ARN=$cluster_arn,SECRET_ARN=$secret_arn,DATABASE=mydb}"

    local lambda_arn=$(aws lambda get-function --function-name "${name}-resolver" --query 'Configuration.FunctionArn' --output text)

    # Initialize database
    log_step "Initializing database..."
    aws rds-data execute-statement \
        --resource-arn "$cluster_arn" \
        --secret-arn "$secret_arn" \
        --sql "CREATE DATABASE IF NOT EXISTS mydb" 2>/dev/null || true

    aws rds-data execute-statement \
        --resource-arn "$cluster_arn" \
        --secret-arn "$secret_arn" \
        --database "mydb" \
        --sql "CREATE TABLE IF NOT EXISTS users (id VARCHAR(36) PRIMARY KEY, name VARCHAR(255), email VARCHAR(255))" 2>/dev/null || true

    # Create AppSync API
    log_step "Creating AppSync API..."
    local api_id=$(aws appsync create-graphql-api \
        --name "$name" \
        --authentication-type API_KEY \
        --query 'graphqlApi.apiId' --output text)

    local expires=$(python3 -c "import time; print(int(time.time()) + 365*24*60*60)")
    local api_key=$(aws appsync create-api-key --api-id "$api_id" --expires "$expires" --query 'apiKey.id' --output text)

    # Create schema
    local schema='type User {
    id: ID!
    name: String!
    email: String!
}

input CreateUserInput {
    name: String!
    email: String!
}

type Query {
    getUser(id: ID!): User
    listUsers: [User]
}

type Mutation {
    createUser(input: CreateUserInput!): User
    deleteUser(id: ID!): User
}

schema {
    query: Query
    mutation: Mutation
}'

    local schema_base64=$(echo "$schema" | base64 | tr -d '\n')
    aws appsync start-schema-creation --api-id "$api_id" --definition "$schema_base64"

    local status="PROCESSING"
    while [ "$status" == "PROCESSING" ]; do
        sleep 2
        status=$(aws appsync get-schema-creation-status --api-id "$api_id" --query 'status' --output text)
    done

    # Create datasource
    local ds_role="${name}-appsync-lambda-role"
    local ds_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"appsync.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$ds_role" --assume-role-policy-document "$ds_trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$ds_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole 2>/dev/null || true

    sleep 10

    aws appsync create-data-source \
        --api-id "$api_id" \
        --name "LambdaResolver" \
        --type AWS_LAMBDA \
        --lambda-config "lambdaFunctionArn=$lambda_arn" \
        --service-role-arn "arn:aws:iam::$account_id:role/$ds_role"

    # Create resolvers
    for resolver in "Query:getUser" "Query:listUsers" "Mutation:createUser" "Mutation:deleteUser"; do
        local type_name=$(echo $resolver | cut -d: -f1)
        local field_name=$(echo $resolver | cut -d: -f2)

        aws appsync create-resolver \
            --api-id "$api_id" \
            --type-name "$type_name" \
            --field-name "$field_name" \
            --data-source-name "LambdaResolver" \
            --request-mapping-template "{
                \"version\": \"2017-02-28\",
                \"operation\": \"Invoke\",
                \"payload\": {
                    \"field\": \"$field_name\",
                    \"arguments\": \$utils.toJson(\$context.arguments)
                }
            }" \
            --response-mapping-template '$util.toJson($ctx.result)'
    done

    rm -rf "$lambda_dir"

    local endpoint=$(aws appsync get-graphql-api --api-id "$api_id" --query 'graphqlApi.uris.GRAPHQL' --output text)

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "API ID: $api_id"
    echo "API Key: $api_key"
    echo "Endpoint: $endpoint"
    echo "VPC ID: $vpc_id"
    echo "Aurora Cluster: $name"
    echo ""
    echo "Test queries:"
    echo ""
    echo "# Create user"
    echo "curl -X POST '$endpoint' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'x-api-key: $api_key' \\"
    echo "  -d '{\"query\": \"mutation { createUser(input: {name: \\\"John\\\", email: \\\"john@example.com\\\"}) { id name email } }\"}'"
    echo ""
    echo "# List users"
    echo "curl -X POST '$endpoint' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'x-api-key: $api_key' \\"
    echo "  -d '{\"query\": \"{ listUsers { id name email } }\"}'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Delete AppSync API
    local api_id=$(aws appsync list-graphql-apis --query "graphqlApis[?name=='$name'].apiId" --output text)
    [ -n "$api_id" ] && aws appsync delete-graphql-api --api-id "$api_id"

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-resolver" 2>/dev/null || true

    # Delete Aurora
    aws rds delete-db-instance --db-instance-identifier "${name}-instance" --skip-final-snapshot 2>/dev/null || true
    aws rds wait db-instance-deleted --db-instance-identifier "${name}-instance" 2>/dev/null || true
    aws rds delete-db-cluster --db-cluster-identifier "$name" --skip-final-snapshot 2>/dev/null || true
    aws rds wait db-cluster-deleted --db-cluster-identifier "$name" 2>/dev/null || true

    # Delete subnet group
    aws rds delete-db-subnet-group --db-subnet-group-name "${name}-subnet-group" 2>/dev/null || true

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

    # Delete IAM roles
    for role in "${name}-lambda-role" "${name}-appsync-lambda-role"; do
        for policy in AWSLambdaBasicExecutionRole AWSLambdaVPCAccessExecutionRole AmazonRDSDataFullAccess SecretsManagerReadWrite AWSLambdaRole; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "arn:aws:iam::aws:policy/service-role/$policy" 2>/dev/null || true
            aws iam detach-role-policy --role-name "$role" --policy-arn "arn:aws:iam::aws:policy/$policy" 2>/dev/null || true
        done
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    done

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== AppSync APIs ===${NC}"
    api_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== Aurora Clusters ===${NC}"
    cluster_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-get-url) api_get_url "$@" ;;
    schema-update) schema_update "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-update) lambda_update "$@" ;;
    cluster-create) cluster_create "$@" ;;
    cluster-delete) cluster_delete "$@" ;;
    cluster-list) cluster_list ;;
    cluster-start) cluster_start "$@" ;;
    cluster-stop) cluster_stop "$@" ;;
    query) db_query "$@" ;;
    vpc-create) vpc_create "$@" ;;
    vpc-delete) vpc_delete "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
