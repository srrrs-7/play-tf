#!/bin/bash

set -e

# CloudFront → App Runner → RDS Architecture Script
# Provides operations for managing a fully managed container architecture

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_CPU="1 vCPU"
DEFAULT_MEMORY="2 GB"
DEFAULT_RDS_INSTANCE_CLASS="db.t3.micro"

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → App Runner → RDS Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status <stack-name>                  - Show status of all components"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <service-url> <stack-name> - Create CloudFront distribution"
    echo "  cf-delete <distribution-id>          - Delete CloudFront distribution"
    echo "  cf-list                              - List CloudFront distributions"
    echo "  cf-invalidate <dist-id> <path>       - Invalidate CloudFront cache"
    echo ""
    echo "App Runner Commands:"
    echo "  apprunner-create-from-ecr <name> <image-uri> [port] - Create service from ECR image"
    echo "  apprunner-create-from-repo <name> <repo-url> <branch> [port] - Create service from code repository"
    echo "  apprunner-delete <service-arn>       - Delete App Runner service"
    echo "  apprunner-list                       - List App Runner services"
    echo "  apprunner-status <service-arn>       - Show service status"
    echo "  apprunner-logs <service-arn>         - View service logs"
    echo "  apprunner-update <service-arn>       - Trigger new deployment"
    echo "  apprunner-pause <service-arn>        - Pause service"
    echo "  apprunner-resume <service-arn>       - Resume service"
    echo "  apprunner-autoscaling <service-arn> <min> <max> - Configure auto scaling"
    echo "  connection-create <name>             - Create GitHub connection"
    echo "  connection-list                      - List connections"
    echo "  vpc-connector-create <name> <subnet-ids> <sg-ids> - Create VPC connector"
    echo "  vpc-connector-delete <arn>           - Delete VPC connector"
    echo "  vpc-connector-list                   - List VPC connectors"
    echo ""
    echo "ECR Commands:"
    echo "  ecr-create <name>                    - Create ECR repository"
    echo "  ecr-delete <name>                    - Delete ECR repository"
    echo "  ecr-list                             - List ECR repositories"
    echo "  ecr-login                            - Login to ECR"
    echo "  ecr-push <repo> <local-image> <tag>  - Push image to ECR"
    echo ""
    echo "RDS Commands:"
    echo "  rds-create <identifier> <engine> <username> <password> <subnet-group> <sg-id> - Create RDS instance"
    echo "  rds-delete <identifier>              - Delete RDS instance"
    echo "  rds-list                             - List RDS instances"
    echo "  rds-status <identifier>              - Show RDS instance status"
    echo "  subnet-group-create <name> <subnet-ids> - Create DB subnet group"
    echo "  subnet-group-delete <name>           - Delete DB subnet group"
    echo ""
    echo "VPC Commands:"
    echo "  vpc-create <name> <cidr>             - Create VPC with subnets"
    echo "  vpc-delete <vpc-id>                  - Delete VPC"
    echo "  vpc-list                             - List VPCs"
    echo "  sg-create <name> <vpc-id> <description> - Create Security Group"
    echo "  sg-delete <sg-id>                    - Delete Security Group"
    echo ""
    exit 1
}

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Run 'aws configure' first."
        exit 1
    fi
}

# Get AWS Account ID
get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

# ============================================
# VPC Functions
# ============================================

vpc_create() {
    local name=$1
    local cidr=${2:-"10.0.0.0/16"}

    if [ -z "$name" ]; then
        log_error "VPC name is required"
        exit 1
    fi

    log_step "Creating VPC: $name with CIDR $cidr"

    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name}]" \
        --query 'Vpc.VpcId' --output text)

    log_info "Created VPC: $vpc_id"

    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames

    # Create Internet Gateway
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$name-igw}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)

    aws ec2 attach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
    log_info "Created and attached Internet Gateway: $igw_id"

    # Get AZs
    local azs
    azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az_array=($azs)

    # Create public subnets
    local public_subnet_1
    public_subnet_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.1.0/24" \
        --availability-zone "${az_array[0]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-1}]" \
        --query 'Subnet.SubnetId' --output text)

    local public_subnet_2
    public_subnet_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.2.0/24" \
        --availability-zone "${az_array[1]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-2}]" \
        --query 'Subnet.SubnetId' --output text)

    log_info "Created public subnets: $public_subnet_1, $public_subnet_2"

    # Create private subnets
    local private_subnet_1
    private_subnet_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.11.0/24" \
        --availability-zone "${az_array[0]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-1}]" \
        --query 'Subnet.SubnetId' --output text)

    local private_subnet_2
    private_subnet_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.12.0/24" \
        --availability-zone "${az_array[1]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-2}]" \
        --query 'Subnet.SubnetId' --output text)

    log_info "Created private subnets: $private_subnet_1, $private_subnet_2"

    # Create public route table
    local public_rt
    public_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-public-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route --route-table-id "$public_rt" --destination-cidr-block "0.0.0.0/0" --gateway-id "$igw_id"
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_1"
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_2"

    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_1" --map-public-ip-on-launch
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_2" --map-public-ip-on-launch

    echo ""
    echo -e "${GREEN}VPC Created Successfully${NC}"
    echo "VPC ID: $vpc_id"
    echo "Public Subnets: $public_subnet_1, $public_subnet_2"
    echo "Private Subnets: $private_subnet_1, $private_subnet_2"
}

vpc_delete() {
    local vpc_id=$1

    if [ -z "$vpc_id" ]; then
        log_error "VPC ID is required"
        exit 1
    fi

    log_warn "This will delete VPC $vpc_id and all associated resources"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting VPC: $vpc_id"

    # Detach and delete Internet Gateway
    local igw
    igw=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ "$igw" != "None" ] && [ -n "$igw" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    fi

    # Delete subnets
    local subnets
    subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text)
    for subnet in $subnets; do
        aws ec2 delete-subnet --subnet-id "$subnet"
    done

    # Delete route tables
    local route_tables
    route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for rt in $route_tables; do
        aws ec2 delete-route-table --route-table-id "$rt"
    done

    # Delete security groups
    local security_groups
    security_groups=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for sg in $security_groups; do
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_info "VPC deleted successfully"
}

vpc_list() {
    log_info "Listing VPCs..."
    aws ec2 describe-vpcs \
        --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],State:State}' \
        --output table
}

sg_create() {
    local name=$1
    local vpc_id=$2
    local description=${3:-"Security group for $name"}

    if [ -z "$name" ] || [ -z "$vpc_id" ]; then
        log_error "Security group name and VPC ID are required"
        exit 1
    fi

    log_step "Creating security group: $name"

    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "$description" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name}]" \
        --query 'GroupId' --output text)

    log_info "Created security group: $sg_id"
    echo "$sg_id"
}

sg_delete() {
    local sg_id=$1

    if [ -z "$sg_id" ]; then
        log_error "Security group ID is required"
        exit 1
    fi

    aws ec2 delete-security-group --group-id "$sg_id"
    log_info "Security group deleted"
}

# ============================================
# ECR Functions
# ============================================

ecr_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Repository name is required"
        exit 1
    fi

    log_step "Creating ECR repository: $name"

    local repo_uri
    repo_uri=$(aws ecr create-repository \
        --repository-name "$name" \
        --image-scanning-configuration scanOnPush=true \
        --query 'repository.repositoryUri' --output text)

    log_info "Created ECR repository: $repo_uri"
    echo "$repo_uri"
}

ecr_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Repository name is required"
        exit 1
    fi

    log_warn "This will delete ECR repository: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    aws ecr delete-repository --repository-name "$name" --force
    log_info "ECR repository deleted"
}

ecr_list() {
    log_info "Listing ECR repositories..."
    aws ecr describe-repositories \
        --query 'repositories[].{Name:repositoryName,URI:repositoryUri}' \
        --output table
}

ecr_login() {
    log_step "Logging in to ECR..."
    local account_id
    account_id=$(get_account_id)

    aws ecr get-login-password --region "$DEFAULT_REGION" | \
        docker login --username AWS --password-stdin "$account_id.dkr.ecr.$DEFAULT_REGION.amazonaws.com"

    log_info "ECR login successful"
}

ecr_push() {
    local repo=$1
    local local_image=$2
    local tag=${3:-latest}

    if [ -z "$repo" ] || [ -z "$local_image" ]; then
        log_error "Repository name and local image are required"
        exit 1
    fi

    local account_id
    account_id=$(get_account_id)
    local ecr_uri="$account_id.dkr.ecr.$DEFAULT_REGION.amazonaws.com/$repo:$tag"

    ecr_login
    docker tag "$local_image" "$ecr_uri"
    docker push "$ecr_uri"

    log_info "Image pushed successfully: $ecr_uri"
    echo "$ecr_uri"
}

# ============================================
# App Runner Functions
# ============================================

apprunner_create_from_ecr() {
    local name=$1
    local image_uri=$2
    local port=${3:-8080}

    if [ -z "$name" ] || [ -z "$image_uri" ]; then
        log_error "Service name and image URI are required"
        exit 1
    fi

    log_step "Creating App Runner service from ECR: $name"

    local account_id
    account_id=$(get_account_id)

    # Create access role for ECR
    local role_name="${name}-apprunner-ecr-role"
    local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "build.apprunner.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
)

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess 2>/dev/null || true

    local role_arn="arn:aws:iam::$account_id:role/$role_name"

    log_info "Waiting for role to propagate..."
    sleep 10

    # Create App Runner service
    local service_config=$(cat << EOF
{
    "ServiceName": "$name",
    "SourceConfiguration": {
        "ImageRepository": {
            "ImageIdentifier": "$image_uri",
            "ImageConfiguration": {
                "Port": "$port"
            },
            "ImageRepositoryType": "ECR"
        },
        "AutoDeploymentsEnabled": true,
        "AuthenticationConfiguration": {
            "AccessRoleArn": "$role_arn"
        }
    },
    "InstanceConfiguration": {
        "Cpu": "$DEFAULT_CPU",
        "Memory": "$DEFAULT_MEMORY"
    }
}
EOF
)

    local service_arn
    service_arn=$(aws apprunner create-service \
        --cli-input-json "$service_config" \
        --query 'Service.ServiceArn' --output text)

    log_info "App Runner service creation initiated"
    log_info "Service ARN: $service_arn"
    log_info "Waiting for service to be running..."

    aws apprunner wait service-running --service-arn "$service_arn" 2>/dev/null || true

    local service_url
    service_url=$(aws apprunner describe-service \
        --service-arn "$service_arn" \
        --query 'Service.ServiceUrl' --output text)

    echo ""
    echo -e "${GREEN}App Runner Service Created${NC}"
    echo "Service ARN: $service_arn"
    echo "Service URL: https://$service_url"
}

apprunner_create_from_repo() {
    local name=$1
    local repo_url=$2
    local branch=${3:-main}
    local port=${4:-8080}

    if [ -z "$name" ] || [ -z "$repo_url" ]; then
        log_error "Service name and repository URL are required"
        exit 1
    fi

    log_step "Creating App Runner service from repository: $name"

    # First, you need a connection to the repository
    log_warn "Note: You must first create a connection using 'connection-create' command"
    log_info "Then use the ConnectionArn in the service configuration"

    echo "Example service creation with GitHub connection:"
    echo ""
    echo "aws apprunner create-service \\"
    echo "  --service-name $name \\"
    echo "  --source-configuration '{\"CodeRepository\":{\"RepositoryUrl\":\"$repo_url\",\"SourceCodeVersion\":{\"Type\":\"BRANCH\",\"Value\":\"$branch\"},\"CodeConfiguration\":{\"ConfigurationSource\":\"API\",\"CodeConfigurationValues\":{\"Runtime\":\"NODEJS_16\",\"Port\":\"$port\"}}},\"AutoDeploymentsEnabled\":true,\"AuthenticationConfiguration\":{\"ConnectionArn\":\"YOUR_CONNECTION_ARN\"}}'"
}

apprunner_delete() {
    local service_arn=$1

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    log_warn "This will delete App Runner service: $service_arn"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting App Runner service"
    aws apprunner delete-service --service-arn "$service_arn"
    log_info "Service deletion initiated"
}

apprunner_list() {
    log_info "Listing App Runner services..."
    aws apprunner list-services \
        --query 'ServiceSummaryList[].{Name:ServiceName,Status:Status,Arn:ServiceArn,Url:ServiceUrl}' \
        --output table
}

apprunner_status() {
    local service_arn=$1

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    log_info "App Runner service status"
    aws apprunner describe-service \
        --service-arn "$service_arn" \
        --query 'Service.{Name:ServiceName,Status:Status,Url:ServiceUrl,Created:CreatedAt,Updated:UpdatedAt}' \
        --output table
}

apprunner_logs() {
    local service_arn=$1

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    # Get service name from ARN
    local service_name
    service_name=$(aws apprunner describe-service \
        --service-arn "$service_arn" \
        --query 'Service.ServiceName' --output text)

    log_info "Fetching logs for App Runner service: $service_name"

    # App Runner logs are in CloudWatch
    local log_group="/aws/apprunner/${service_name}"
    aws logs tail "$log_group" --follow 2>/dev/null || log_warn "Log group not found: $log_group"
}

apprunner_update() {
    local service_arn=$1

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    log_step "Triggering new deployment for App Runner service"
    aws apprunner start-deployment --service-arn "$service_arn"
    log_info "Deployment started"
}

apprunner_pause() {
    local service_arn=$1

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    log_step "Pausing App Runner service"
    aws apprunner pause-service --service-arn "$service_arn"
    log_info "Service paused"
}

apprunner_resume() {
    local service_arn=$1

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    log_step "Resuming App Runner service"
    aws apprunner resume-service --service-arn "$service_arn"
    log_info "Service resumed"
}

apprunner_autoscaling() {
    local service_arn=$1
    local min=${2:-1}
    local max=${3:-10}

    if [ -z "$service_arn" ]; then
        log_error "Service ARN is required"
        exit 1
    fi

    log_step "Creating auto scaling configuration"

    local config_arn
    config_arn=$(aws apprunner create-auto-scaling-configuration \
        --auto-scaling-configuration-name "scaling-${min}-${max}" \
        --max-concurrency 100 \
        --min-size "$min" \
        --max-size "$max" \
        --query 'AutoScalingConfiguration.AutoScalingConfigurationArn' --output text)

    log_info "Auto scaling configuration created: $config_arn"

    # Update service with new auto scaling config
    aws apprunner update-service \
        --service-arn "$service_arn" \
        --auto-scaling-configuration-arn "$config_arn"

    log_info "Service updated with auto scaling configuration"
}

connection_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Connection name is required"
        exit 1
    fi

    log_step "Creating GitHub connection: $name"

    local connection_arn
    connection_arn=$(aws apprunner create-connection \
        --connection-name "$name" \
        --provider-type GITHUB \
        --query 'Connection.ConnectionArn' --output text)

    log_info "Connection created: $connection_arn"
    log_warn "IMPORTANT: You must complete the connection in the AWS Console"
    log_warn "Go to: https://console.aws.amazon.com/apprunner/home#/connections"
    echo "$connection_arn"
}

connection_list() {
    log_info "Listing App Runner connections..."
    aws apprunner list-connections \
        --query 'ConnectionSummaryList[].{Name:ConnectionName,Status:Status,Arn:ConnectionArn}' \
        --output table
}

vpc_connector_create() {
    local name=$1
    local subnet_ids=$2  # comma-separated
    local sg_ids=$3      # comma-separated

    if [ -z "$name" ] || [ -z "$subnet_ids" ] || [ -z "$sg_ids" ]; then
        log_error "Name, subnet IDs, and security group IDs are required"
        exit 1
    fi

    log_step "Creating VPC connector: $name"

    local connector_arn
    connector_arn=$(aws apprunner create-vpc-connector \
        --vpc-connector-name "$name" \
        --subnets ${subnet_ids//,/ } \
        --security-groups ${sg_ids//,/ } \
        --query 'VpcConnector.VpcConnectorArn' --output text)

    log_info "VPC connector created: $connector_arn"
    echo "$connector_arn"
}

vpc_connector_delete() {
    local arn=$1

    if [ -z "$arn" ]; then
        log_error "VPC connector ARN is required"
        exit 1
    fi

    log_step "Deleting VPC connector"
    aws apprunner delete-vpc-connector --vpc-connector-arn "$arn"
    log_info "VPC connector deleted"
}

vpc_connector_list() {
    log_info "Listing VPC connectors..."
    aws apprunner list-vpc-connectors \
        --query 'VpcConnectors[].{Name:VpcConnectorName,Status:Status,Arn:VpcConnectorArn}' \
        --output table
}

# ============================================
# RDS Functions
# ============================================

subnet_group_create() {
    local name=$1
    local subnet_ids=$2  # comma-separated

    if [ -z "$name" ] || [ -z "$subnet_ids" ]; then
        log_error "Subnet group name and subnet IDs are required"
        exit 1
    fi

    log_step "Creating DB Subnet Group: $name"

    aws rds create-db-subnet-group \
        --db-subnet-group-name "$name" \
        --db-subnet-group-description "Subnet group for $name" \
        --subnet-ids ${subnet_ids//,/ }

    log_info "Created DB Subnet Group: $name"
}

subnet_group_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Subnet group name is required"
        exit 1
    fi

    aws rds delete-db-subnet-group --db-subnet-group-name "$name"
    log_info "DB Subnet Group deleted"
}

rds_create() {
    local identifier=$1
    local engine=${2:-mysql}
    local username=$3
    local password=$4
    local subnet_group=$5
    local sg_id=$6

    if [ -z "$identifier" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$subnet_group" ]; then
        log_error "RDS identifier, username, password, and subnet group are required"
        exit 1
    fi

    log_step "Creating RDS instance: $identifier"

    local rds_args="--db-instance-identifier $identifier"
    rds_args="$rds_args --db-instance-class $DEFAULT_RDS_INSTANCE_CLASS"
    rds_args="$rds_args --engine $engine"
    rds_args="$rds_args --master-username $username"
    rds_args="$rds_args --master-user-password $password"
    rds_args="$rds_args --allocated-storage 20"
    rds_args="$rds_args --db-subnet-group-name $subnet_group"
    rds_args="$rds_args --no-publicly-accessible"
    rds_args="$rds_args --backup-retention-period 7"

    if [ -n "$sg_id" ]; then
        rds_args="$rds_args --vpc-security-group-ids $sg_id"
    fi

    aws rds create-db-instance $rds_args

    log_info "RDS instance creation initiated. This may take several minutes..."
    log_info "Use 'rds-status $identifier' to check the status"
}

rds_delete() {
    local identifier=$1

    if [ -z "$identifier" ]; then
        log_error "RDS identifier is required"
        exit 1
    fi

    log_warn "This will delete RDS instance: $identifier"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting RDS instance: $identifier"

    aws rds delete-db-instance \
        --db-instance-identifier "$identifier" \
        --skip-final-snapshot \
        --delete-automated-backups

    log_info "RDS deletion initiated"
}

rds_list() {
    log_info "Listing RDS instances..."
    aws rds describe-db-instances \
        --query 'DBInstances[].{Identifier:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
        --output table
}

rds_status() {
    local identifier=$1

    if [ -z "$identifier" ]; then
        log_error "RDS identifier is required"
        exit 1
    fi

    log_info "RDS instance status: $identifier"
    aws rds describe-db-instances \
        --db-instance-identifier "$identifier" \
        --query 'DBInstances[0].{Identifier:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine,EngineVersion:EngineVersion,Class:DBInstanceClass,Endpoint:Endpoint.Address,Port:Endpoint.Port}' \
        --output table
}

# ============================================
# CloudFront Functions
# ============================================

cf_create() {
    local service_url=$1
    local stack_name=$2

    if [ -z "$service_url" ] || [ -z "$stack_name" ]; then
        log_error "App Runner service URL and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution for App Runner"

    # Remove https:// if present
    local domain
    domain=$(echo "$service_url" | sed 's|https://||')

    local dist_config=$(cat << EOF
{
    "CallerReference": "$stack_name-$(date +%s)",
    "Comment": "CloudFront for App Runner $stack_name",
    "DefaultCacheBehavior": {
        "TargetOriginId": "AppRunner-$stack_name",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
        "CachedMethods": ["GET", "HEAD"],
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {"Forward": "all"},
            "Headers": ["Host", "Origin", "Authorization"]
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0,
        "Compress": true
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "AppRunner-$stack_name",
            "DomainName": "$domain",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "https-only",
                "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]}
            }
        }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_200"
}
EOF
)

    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --query 'Distribution.Id' --output text)

    local domain_name
    domain_name=$(aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.DomainName' --output text)

    log_info "CloudFront distribution created"
    echo ""
    echo -e "${GREEN}CloudFront Distribution Created${NC}"
    echo "Distribution ID: $dist_id"
    echo "Domain Name: $domain_name"
}

cf_delete() {
    local dist_id=$1

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_warn "This will delete CloudFront distribution: $dist_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Disabling CloudFront distribution"

    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)

    local disabled_config
    disabled_config=$(echo "$config" | jq '.Enabled = false')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$disabled_config"

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"

    log_info "CloudFront distribution deleted"
}

cf_list() {
    log_info "Listing CloudFront distributions..."
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Enabled:Enabled,Comment:Comment}' \
        --output table
}

cf_invalidate() {
    local dist_id=$1
    local path=${2:-"/*"}

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    aws cloudfront create-invalidation --distribution-id "$dist_id" --paths "$path"
    log_info "Invalidation created"
}

# ============================================
# Full Stack Deploy/Destroy
# ============================================

deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_info "Deploying App Runner architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets"
    echo "  - ECR repository"
    echo "  - RDS instance"
    echo "  - App Runner service"
    echo "  - CloudFront distribution"
    echo ""
    echo "Prerequisites:"
    echo "  - Docker image to deploy"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Create VPC
    log_step "Step 1/5: Creating VPC..."
    vpc_create "$stack_name"

    log_info "VPC created. Please note the subnet IDs for the next steps."
    echo ""
    echo "Next steps:"
    echo "  1. Create ECR repository: ecr-create $stack_name"
    echo "  2. Build and push Docker image: ecr-push $stack_name <local-image> <tag>"
    echo "  3. Create DB subnet group: subnet-group-create $stack_name-db <private-subnet-ids>"
    echo "  4. Create RDS: rds-create $stack_name-db mysql <username> <password> $stack_name-db <sg-id>"
    echo "  5. Create VPC connector: vpc-connector-create $stack_name-vpc <private-subnet-ids> <sg-ids>"
    echo "  6. Create App Runner: apprunner-create-from-ecr $stack_name <image-uri>"
    echo "  7. Create CloudFront: cf-create <service-url> $stack_name"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_warn "Recommended deletion order for: $stack_name"
    echo ""
    echo "  1. Delete CloudFront distribution"
    echo "  2. Delete App Runner service"
    echo "  3. Delete VPC connector"
    echo "  4. Delete RDS instance"
    echo "  5. Delete DB Subnet Group"
    echo "  6. Delete ECR repository"
    echo "  7. Delete Security Groups"
    echo "  8. Delete VPC"
    echo ""

    log_info "Use individual delete commands with resource IDs"
}

status() {
    local stack_name=$1

    log_info "Checking status for: $stack_name"
    echo ""

    echo -e "${BLUE}=== App Runner Services ===${NC}"
    apprunner_list

    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list

    echo -e "\n${BLUE}=== RDS Instances ===${NC}"
    rds_list

    echo -e "\n${BLUE}=== ECR Repositories ===${NC}"
    ecr_list

    echo -e "\n${BLUE}=== VPC Connectors ===${NC}"
    vpc_connector_list

    echo -e "\n${BLUE}=== VPCs ===${NC}"
    vpc_list
}

# ============================================
# Main Script Logic
# ============================================

check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    # Full stack
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status "$@" ;;

    # VPC
    vpc-create) vpc_create "$@" ;;
    vpc-delete) vpc_delete "$@" ;;
    vpc-list) vpc_list ;;
    sg-create) sg_create "$@" ;;
    sg-delete) sg_delete "$@" ;;

    # ECR
    ecr-create) ecr_create "$@" ;;
    ecr-delete) ecr_delete "$@" ;;
    ecr-list) ecr_list ;;
    ecr-login) ecr_login ;;
    ecr-push) ecr_push "$@" ;;

    # App Runner
    apprunner-create-from-ecr) apprunner_create_from_ecr "$@" ;;
    apprunner-create-from-repo) apprunner_create_from_repo "$@" ;;
    apprunner-delete) apprunner_delete "$@" ;;
    apprunner-list) apprunner_list ;;
    apprunner-status) apprunner_status "$@" ;;
    apprunner-logs) apprunner_logs "$@" ;;
    apprunner-update) apprunner_update "$@" ;;
    apprunner-pause) apprunner_pause "$@" ;;
    apprunner-resume) apprunner_resume "$@" ;;
    apprunner-autoscaling) apprunner_autoscaling "$@" ;;
    connection-create) connection_create "$@" ;;
    connection-list) connection_list ;;
    vpc-connector-create) vpc_connector_create "$@" ;;
    vpc-connector-delete) vpc_connector_delete "$@" ;;
    vpc-connector-list) vpc_connector_list ;;

    # RDS
    rds-create) rds_create "$@" ;;
    rds-delete) rds_delete "$@" ;;
    rds-list) rds_list ;;
    rds-status) rds_status "$@" ;;
    subnet-group-create) subnet_group_create "$@" ;;
    subnet-group-delete) subnet_group_delete "$@" ;;

    # CloudFront
    cf-create) cf_create "$@" ;;
    cf-delete) cf_delete "$@" ;;
    cf-list) cf_list ;;
    cf-invalidate) cf_invalidate "$@" ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
