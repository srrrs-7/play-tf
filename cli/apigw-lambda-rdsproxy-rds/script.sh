#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# API Gateway → Lambda → RDS Proxy → RDS Architecture Script
# Provides operations for serverless API with connection pooling

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RDS_CLASS="db.t3.micro"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "API Gateway → Lambda → RDS Proxy → RDS Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full architecture"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "RDS Proxy:"
    echo "  proxy-create <name> <rds-arn> <secret-arn> <subnet-ids> <sg-id> - Create RDS Proxy"
    echo "  proxy-delete <name>                  - Delete RDS Proxy"
    echo "  proxy-list                           - List proxies"
    echo "  proxy-status <name>                  - Show proxy status"
    echo "  proxy-target-register <proxy> <rds-id> - Register target"
    echo ""
    echo "RDS:"
    echo "  rds-create <id> <username> <password> <subnet-group> [sg-id] - Create RDS"
    echo "  rds-delete <id>                      - Delete RDS"
    echo "  rds-list                             - List instances"
    echo "  subnet-group-create <name> <subnet-ids> - Create subnet group"
    echo ""
    echo "Secrets Manager:"
    echo "  secret-create <name> <username> <password> <host> [port] - Create DB secret"
    echo "  secret-delete <name>                 - Delete secret"
    echo "  secret-list                          - List secrets"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip> <proxy-endpoint> <secret-arn> <sg-id> <subnet-ids> - Create"
    echo "  lambda-delete <name>                 - Delete"
    echo "  lambda-list                          - List"
    echo ""
    echo "API Gateway:"
    echo "  api-create <name>                    - Create API"
    echo "  api-delete <id>                      - Delete API"
    echo "  api-deploy <id> <stage>              - Deploy API"
    echo ""
    echo "VPC:"
    echo "  vpc-create <name>                    - Create VPC"
    echo "  vpc-delete <vpc-id>                  - Delete VPC"
    echo ""
    exit 1
}

# Secrets Manager
secret_create() {
    local name=$1
    local username=$2
    local password=$3
    local host=$4
    local port=${5:-3306}

    [ -z "$name" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$host" ] && {
        log_error "Name, username, password, and host required"
        exit 1
    }

    log_step "Creating secret: $name"

    local secret_string=$(cat << EOF
{
    "username": "$username",
    "password": "$password",
    "engine": "mysql",
    "host": "$host",
    "port": $port,
    "dbname": "mydb"
}
EOF
)

    local secret_arn
    secret_arn=$(aws secretsmanager create-secret \
        --name "$name" \
        --secret-string "$secret_string" \
        --query 'ARN' --output text)

    log_info "Secret created: $secret_arn"
    echo "$secret_arn"
}

secret_delete() {
    local name=$1
    aws secretsmanager delete-secret --secret-id "$name" --force-delete-without-recovery
    log_info "Secret deleted"
}

secret_list() {
    aws secretsmanager list-secrets --query 'SecretList[].{Name:Name,ARN:ARN}' --output table
}

# RDS Proxy
proxy_create() {
    local name=$1
    local rds_arn=$2
    local secret_arn=$3
    local subnet_ids=$4
    local sg_id=$5

    [ -z "$name" ] || [ -z "$secret_arn" ] || [ -z "$subnet_ids" ] && {
        log_error "Name, secret ARN, and subnet IDs required"
        exit 1
    }

    log_step "Creating RDS Proxy: $name"

    local account_id=$(get_account_id)

    # Create IAM role for proxy
    local role_name="${name}-proxy-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"rds.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue"],
        "Resource": ["$secret_arn"]
    }]
}
EOF
)

    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-secrets-policy" --policy-document "$policy"

    sleep 10

    local role_arn="arn:aws:iam::$account_id:role/$role_name"

    # Create proxy
    local proxy_args="--db-proxy-name $name"
    proxy_args="$proxy_args --engine-family MYSQL"
    proxy_args="$proxy_args --role-arn $role_arn"
    proxy_args="$proxy_args --vpc-subnet-ids ${subnet_ids//,/ }"

    if [ -n "$sg_id" ]; then
        proxy_args="$proxy_args --vpc-security-group-ids $sg_id"
    fi

    proxy_args="$proxy_args --auth Description=\"Auth\",AuthScheme=SECRETS,SecretArn=$secret_arn,IAMAuth=DISABLED"

    aws rds create-db-proxy $proxy_args

    log_info "RDS Proxy creation initiated"
    log_info "Waiting for proxy to be available..."

    aws rds wait db-proxy-available --db-proxy-name "$name" 2>/dev/null || sleep 60

    local endpoint
    endpoint=$(aws rds describe-db-proxies --db-proxy-name "$name" --query 'DBProxies[0].Endpoint' --output text)

    log_info "Proxy endpoint: $endpoint"
}

proxy_delete() {
    local name=$1
    log_warn "Deleting proxy: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws rds delete-db-proxy --db-proxy-name "$name"
    log_info "Proxy deleted"
}

proxy_list() {
    aws rds describe-db-proxies \
        --query 'DBProxies[].{Name:DBProxyName,Status:Status,Endpoint:Endpoint,Engine:EngineFamily}' \
        --output table
}

proxy_status() {
    local name=$1
    aws rds describe-db-proxies \
        --db-proxy-name "$name" \
        --query 'DBProxies[0].{Name:DBProxyName,Status:Status,Endpoint:Endpoint,VpcId:VpcId}' \
        --output table
}

proxy_target_register() {
    local proxy=$1
    local rds_id=$2

    [ -z "$proxy" ] || [ -z "$rds_id" ] && {
        log_error "Proxy name and RDS ID required"
        exit 1
    }

    log_step "Registering target: $rds_id"

    aws rds register-db-proxy-targets \
        --db-proxy-name "$proxy" \
        --db-instance-identifiers "$rds_id"

    log_info "Target registered"
}

# RDS
subnet_group_create() {
    local name=$1
    local subnet_ids=$2

    aws rds create-db-subnet-group \
        --db-subnet-group-name "$name" \
        --db-subnet-group-description "Subnet group for $name" \
        --subnet-ids ${subnet_ids//,/ }

    log_info "Subnet group created"
}

rds_create() {
    local id=$1
    local username=$2
    local password=$3
    local subnet_group=$4
    local sg_id=$5

    [ -z "$id" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$subnet_group" ] && {
        log_error "ID, username, password, and subnet group required"
        exit 1
    }

    log_step "Creating RDS: $id"

    local args="--db-instance-identifier $id"
    args="$args --db-instance-class $DEFAULT_RDS_CLASS"
    args="$args --engine mysql"
    args="$args --master-username $username"
    args="$args --master-user-password $password"
    args="$args --allocated-storage 20"
    args="$args --db-subnet-group-name $subnet_group"
    args="$args --no-publicly-accessible"

    [ -n "$sg_id" ] && args="$args --vpc-security-group-ids $sg_id"

    aws rds create-db-instance $args

    log_info "RDS creation initiated"
}

rds_delete() {
    local id=$1
    log_warn "Deleting RDS: $id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws rds delete-db-instance --db-instance-identifier "$id" --skip-final-snapshot --delete-automated-backups
    log_info "RDS deletion initiated"
}

rds_list() {
    aws rds describe-db-instances \
        --query 'DBInstances[].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
        --output table
}

# Lambda
lambda_create() {
    local name=$1
    local zip_file=$2
    local proxy_endpoint=$3
    local secret_arn=$4
    local sg_id=$5
    local subnet_ids=$6

    if [ -z "$name" ] || [ -z "$zip_file" ] || [ -z "$proxy_endpoint" ]; then
        log_error "Name, zip file, and proxy endpoint required"
        exit 1
    fi

    log_step "Creating Lambda: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    # Create role
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || true

    sleep 10

    local args="--function-name $name"
    args="$args --runtime nodejs18.x"
    args="$args --handler index.handler"
    args="$args --role arn:aws:iam::$account_id:role/$role_name"
    args="$args --zip-file fileb://$zip_file"
    args="$args --timeout 30"
    args="$args --memory-size 256"
    args="$args --environment Variables={PROXY_ENDPOINT=$proxy_endpoint,DB_NAME=mydb}"

    if [ -n "$sg_id" ] && [ -n "$subnet_ids" ]; then
        args="$args --vpc-config SubnetIds=${subnet_ids},SecurityGroupIds=${sg_id}"
    fi

    aws lambda create-function $args

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

# API Gateway
api_create() {
    local name=$1
    local api_id=$(aws apigateway create-rest-api --name "$name" --endpoint-configuration types=REGIONAL --query 'id' --output text)
    log_info "API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local id=$1
    aws apigateway delete-rest-api --rest-api-id "$id"
    log_info "API deleted"
}

api_deploy() {
    local id=$1
    local stage=${2:-prod}
    aws apigateway create-deployment --rest-api-id "$id" --stage-name "$stage"
    log_info "Deployed: https://$id.execute-api.$DEFAULT_REGION.amazonaws.com/$stage"
}

# VPC
vpc_create() {
    local name=$1
    log_step "Creating VPC: $name"

    local vpc_id=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name}]" --query 'Vpc.VpcId' --output text)
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames

    local igw_id=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$name-igw}]" --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 attach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"

    local azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az_arr=($azs)

    local sub1=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "10.0.1.0/24" --availability-zone "${az_arr[0]}" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-1}]" --query 'Subnet.SubnetId' --output text)
    local sub2=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "10.0.2.0/24" --availability-zone "${az_arr[1]}" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-2}]" --query 'Subnet.SubnetId' --output text)

    echo "VPC: $vpc_id"
    echo "Subnets: $sub1, $sub2"
}

vpc_delete() {
    local vpc_id=$1
    log_warn "Deleting VPC: $vpc_id"

    local igw=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[0].InternetGatewayId' --output text)
    [ "$igw" != "None" ] && {
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    }

    for sub in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text); do
        aws ec2 delete-subnet --subnet-id "$sub"
    done

    for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_info "VPC deleted"
}

# Full Stack
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying: $name"
    echo ""
    echo "This will create:"
    echo "  - VPC with private subnets"
    echo "  - RDS MySQL instance"
    echo "  - Secrets Manager secret"
    echo "  - RDS Proxy"
    echo "  - Lambda function"
    echo "  - API Gateway"
    echo ""

    read -p "Continue? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    log_step "Creating VPC..."
    vpc_create "$name"

    log_info "Please note the VPC ID and subnet IDs"
    log_info "Then run the following commands manually:"
    echo ""
    echo "1. Create DB subnet group:"
    echo "   ./script.sh subnet-group-create ${name}-db <subnet1>,<subnet2>"
    echo ""
    echo "2. Create security group for RDS and Lambda"
    echo ""
    echo "3. Create RDS:"
    echo "   ./script.sh rds-create ${name}-db admin <password> ${name}-db <sg-id>"
    echo ""
    echo "4. Create secret (after RDS is available):"
    echo "   ./script.sh secret-create ${name}-secret admin <password> <rds-endpoint>"
    echo ""
    echo "5. Create RDS Proxy:"
    echo "   ./script.sh proxy-create ${name}-proxy <rds-arn> <secret-arn> <subnet-ids> <sg-id>"
    echo ""
    echo "6. Register target:"
    echo "   ./script.sh proxy-target-register ${name}-proxy ${name}-db"
}

destroy() {
    local name=$1
    log_warn "Destruction order:"
    echo "  1. API Gateway"
    echo "  2. Lambda"
    echo "  3. RDS Proxy"
    echo "  4. RDS instance"
    echo "  5. Secrets Manager secret"
    echo "  6. DB Subnet Group"
    echo "  7. VPC"
}

status() {
    echo -e "${BLUE}=== RDS Proxies ===${NC}"
    proxy_list
    echo -e "\n${BLUE}=== RDS Instances ===${NC}"
    rds_list
    echo -e "\n${BLUE}=== Secrets ===${NC}"
    secret_list
    echo -e "\n${BLUE}=== Lambda ===${NC}"
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
    proxy-create) proxy_create "$@" ;;
    proxy-delete) proxy_delete "$@" ;;
    proxy-list) proxy_list ;;
    proxy-status) proxy_status "$@" ;;
    proxy-target-register) proxy_target_register "$@" ;;
    rds-create) rds_create "$@" ;;
    rds-delete) rds_delete "$@" ;;
    rds-list) rds_list ;;
    subnet-group-create) subnet_group_create "$@" ;;
    secret-create) secret_create "$@" ;;
    secret-delete) secret_delete "$@" ;;
    secret-list) secret_list ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-deploy) api_deploy "$@" ;;
    vpc-create) vpc_create "$@" ;;
    vpc-delete) vpc_delete "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
