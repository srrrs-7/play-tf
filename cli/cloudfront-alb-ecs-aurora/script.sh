#!/bin/bash

set -e

# CloudFront → ALB → ECS Fargate → Aurora Architecture Script
# Provides operations for managing a containerized serverless architecture

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_FARGATE_CPU="256"
DEFAULT_FARGATE_MEMORY="512"
DEFAULT_DESIRED_COUNT=2
DEFAULT_AURORA_INSTANCE_CLASS="db.t3.medium"

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → ALB → ECS Fargate → Aurora Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status <stack-name>                  - Show status of all components"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <alb-dns> <stack-name>    - Create CloudFront distribution"
    echo "  cf-delete <distribution-id>          - Delete CloudFront distribution"
    echo "  cf-list                              - List CloudFront distributions"
    echo "  cf-invalidate <dist-id> <path>       - Invalidate CloudFront cache"
    echo ""
    echo "ALB Commands:"
    echo "  alb-create <name> <vpc-id> <subnet-ids> - Create Application Load Balancer"
    echo "  alb-delete <alb-arn>                 - Delete Application Load Balancer"
    echo "  alb-list                             - List Application Load Balancers"
    echo "  tg-create <name> <vpc-id> <port>     - Create Target Group (IP type for Fargate)"
    echo "  tg-delete <tg-arn>                   - Delete Target Group"
    echo "  listener-create <alb-arn> <tg-arn>   - Create HTTP listener"
    echo ""
    echo "ECS Fargate Commands:"
    echo "  cluster-create <name>                - Create ECS cluster"
    echo "  cluster-delete <name>                - Delete ECS cluster"
    echo "  cluster-list                         - List ECS clusters"
    echo "  task-def-create <family> <image> <port> [cpu] [memory] - Create task definition"
    echo "  task-def-delete <family>             - Deregister task definition"
    echo "  task-def-list                        - List task definitions"
    echo "  service-create <cluster> <name> <task-def> <subnet-ids> <sg-id> <tg-arn> - Create Fargate service"
    echo "  service-delete <cluster> <name>      - Delete service"
    echo "  service-list <cluster>               - List services in cluster"
    echo "  service-update <cluster> <name> <desired-count> - Update service"
    echo "  service-logs <cluster> <name>        - View service logs"
    echo ""
    echo "Aurora Commands:"
    echo "  aurora-create <cluster-id> <username> <password> <subnet-group> <sg-id> - Create Aurora cluster"
    echo "  aurora-delete <cluster-id>           - Delete Aurora cluster"
    echo "  aurora-list                          - List Aurora clusters"
    echo "  aurora-status <cluster-id>           - Show Aurora cluster status"
    echo "  aurora-add-instance <cluster-id> <instance-id> - Add instance to cluster"
    echo "  subnet-group-create <name> <subnet-ids> - Create DB subnet group"
    echo "  subnet-group-delete <name>           - Delete DB subnet group"
    echo ""
    echo "ECR Commands:"
    echo "  ecr-create <name>                    - Create ECR repository"
    echo "  ecr-delete <name>                    - Delete ECR repository"
    echo "  ecr-list                             - List ECR repositories"
    echo "  ecr-login                            - Login to ECR"
    echo "  ecr-push <repo> <local-image> <tag>  - Build and push image to ECR"
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

    # Create public subnets in 2 AZs
    local azs
    azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az_array=($azs)

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

    # Create route table for public subnets
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

    # Create NAT Gateway for private subnets (needed for Fargate to pull images)
    log_info "Creating NAT Gateway..."
    local eip_alloc
    eip_alloc=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

    local nat_gw
    nat_gw=$(aws ec2 create-nat-gateway \
        --subnet-id "$public_subnet_1" \
        --allocation-id "$eip_alloc" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$name-nat}]" \
        --query 'NatGateway.NatGatewayId' --output text)

    log_info "Waiting for NAT Gateway to become available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat_gw"

    # Create private route table
    local private_rt
    private_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-private-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route --route-table-id "$private_rt" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "$nat_gw"
    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet_1"
    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet_2"

    log_info "Configured route tables with NAT Gateway"

    echo ""
    echo -e "${GREEN}VPC Created Successfully${NC}"
    echo "VPC ID: $vpc_id"
    echo "Public Subnets: $public_subnet_1, $public_subnet_2"
    echo "Private Subnets: $private_subnet_1, $private_subnet_2"
    echo "NAT Gateway: $nat_gw"
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

    # Delete NAT Gateways
    local nat_gateways
    nat_gateways=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" --query 'NatGateways[].NatGatewayId' --output text)
    for nat in $nat_gateways; do
        log_info "Deleting NAT Gateway: $nat"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat"
    done

    if [ -n "$nat_gateways" ]; then
        log_info "Waiting for NAT Gateways to be deleted..."
        sleep 60
    fi

    # Release Elastic IPs
    local eips
    eips=$(aws ec2 describe-addresses --filters "Name=domain,Values=vpc" --query 'Addresses[].AllocationId' --output text)
    for eip in $eips; do
        log_info "Releasing Elastic IP: $eip"
        aws ec2 release-address --allocation-id "$eip" 2>/dev/null || true
    done

    # Detach and delete Internet Gateway
    local igw
    igw=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ "$igw" != "None" ] && [ -n "$igw" ]; then
        log_info "Detaching and deleting Internet Gateway: $igw"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    fi

    # Delete subnets
    local subnets
    subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text)
    for subnet in $subnets; do
        log_info "Deleting subnet: $subnet"
        aws ec2 delete-subnet --subnet-id "$subnet"
    done

    # Delete route tables
    local route_tables
    route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for rt in $route_tables; do
        log_info "Deleting route table: $rt"
        aws ec2 delete-route-table --route-table-id "$rt"
    done

    # Delete security groups
    local security_groups
    security_groups=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for sg in $security_groups; do
        log_info "Deleting security group: $sg"
        aws ec2 delete-security-group --group-id "$sg"
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

    log_step "Deleting security group: $sg_id"
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
        --encryption-configuration encryptionType=AES256 \
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

    log_warn "This will delete ECR repository: $name and all images"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting ECR repository: $name"
    aws ecr delete-repository --repository-name "$name" --force
    log_info "ECR repository deleted"
}

ecr_list() {
    log_info "Listing ECR repositories..."
    aws ecr describe-repositories \
        --query 'repositories[].{Name:repositoryName,URI:repositoryUri,Created:createdAt}' \
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

    log_step "Pushing image to ECR: $ecr_uri"

    # Login to ECR
    ecr_login

    # Tag and push
    docker tag "$local_image" "$ecr_uri"
    docker push "$ecr_uri"

    log_info "Image pushed successfully: $ecr_uri"
    echo "$ecr_uri"
}

# ============================================
# ECS Cluster Functions
# ============================================

cluster_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_step "Creating ECS cluster: $name"

    aws ecs create-cluster \
        --cluster-name "$name" \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --settings name=containerInsights,value=enabled

    log_info "Created ECS cluster: $name"
}

cluster_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_warn "This will delete ECS cluster: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting ECS cluster: $name"
    aws ecs delete-cluster --cluster "$name"
    log_info "ECS cluster deleted"
}

cluster_list() {
    log_info "Listing ECS clusters..."
    aws ecs list-clusters --query 'clusterArns[]' --output table

    echo ""
    aws ecs describe-clusters \
        --clusters $(aws ecs list-clusters --query 'clusterArns[]' --output text) \
        --query 'clusters[].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,Services:activeServicesCount}' \
        --output table 2>/dev/null || true
}

# ============================================
# ECS Task Definition Functions
# ============================================

task_def_create() {
    local family=$1
    local image=$2
    local port=${3:-80}
    local cpu=${4:-$DEFAULT_FARGATE_CPU}
    local memory=${5:-$DEFAULT_FARGATE_MEMORY}

    if [ -z "$family" ] || [ -z "$image" ]; then
        log_error "Task definition family and image are required"
        exit 1
    fi

    log_step "Creating task definition: $family"

    local account_id
    account_id=$(get_account_id)

    # Create execution role if not exists
    local execution_role_arn="arn:aws:iam::$account_id:role/ecsTaskExecutionRole"

    local task_def=$(cat << EOF
{
    "family": "$family",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "$cpu",
    "memory": "$memory",
    "executionRoleArn": "$execution_role_arn",
    "containerDefinitions": [
        {
            "name": "$family",
            "image": "$image",
            "essential": true,
            "portMappings": [
                {
                    "containerPort": $port,
                    "hostPort": $port,
                    "protocol": "tcp"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/$family",
                    "awslogs-region": "$DEFAULT_REGION",
                    "awslogs-stream-prefix": "ecs",
                    "awslogs-create-group": "true"
                }
            }
        }
    ]
}
EOF
)

    aws ecs register-task-definition --cli-input-json "$task_def"

    log_info "Created task definition: $family"
}

task_def_delete() {
    local family=$1

    if [ -z "$family" ]; then
        log_error "Task definition family is required"
        exit 1
    fi

    log_step "Deregistering task definitions for: $family"

    local task_defs
    task_defs=$(aws ecs list-task-definitions --family-prefix "$family" --query 'taskDefinitionArns[]' --output text)

    for td in $task_defs; do
        log_info "Deregistering: $td"
        aws ecs deregister-task-definition --task-definition "$td" > /dev/null
    done

    log_info "Task definitions deregistered"
}

task_def_list() {
    log_info "Listing task definitions..."
    aws ecs list-task-definitions --query 'taskDefinitionArns[]' --output table
}

# ============================================
# ECS Service Functions
# ============================================

service_create() {
    local cluster=$1
    local name=$2
    local task_def=$3
    local subnet_ids=$4  # comma-separated
    local sg_id=$5
    local tg_arn=$6

    if [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$task_def" ] || [ -z "$subnet_ids" ] || [ -z "$sg_id" ]; then
        log_error "Cluster, service name, task definition, subnet IDs, and security group are required"
        exit 1
    fi

    log_step "Creating ECS service: $name"

    local service_args="--cluster $cluster"
    service_args="$service_args --service-name $name"
    service_args="$service_args --task-definition $task_def"
    service_args="$service_args --desired-count $DEFAULT_DESIRED_COUNT"
    service_args="$service_args --launch-type FARGATE"
    service_args="$service_args --platform-version LATEST"

    # Network configuration
    local subnets_json=$(echo "$subnet_ids" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd,)
    local network_config="{\"awsvpcConfiguration\":{\"subnets\":[$subnets_json],\"securityGroups\":[\"$sg_id\"],\"assignPublicIp\":\"DISABLED\"}}"

    service_args="$service_args --network-configuration $network_config"

    # Load balancer configuration
    if [ -n "$tg_arn" ]; then
        local container_name
        container_name=$(aws ecs describe-task-definition --task-definition "$task_def" --query 'taskDefinition.containerDefinitions[0].name' --output text)
        local container_port
        container_port=$(aws ecs describe-task-definition --task-definition "$task_def" --query 'taskDefinition.containerDefinitions[0].portMappings[0].containerPort' --output text)

        local lb_config="[{\"targetGroupArn\":\"$tg_arn\",\"containerName\":\"$container_name\",\"containerPort\":$container_port}]"
        service_args="$service_args --load-balancers $lb_config"
    fi

    aws ecs create-service $service_args

    log_info "Created ECS service: $name"
}

service_delete() {
    local cluster=$1
    local name=$2

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and service name are required"
        exit 1
    fi

    log_warn "This will delete ECS service: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting ECS service: $name"

    # Scale down to 0
    aws ecs update-service --cluster "$cluster" --service "$name" --desired-count 0

    log_info "Waiting for tasks to stop..."
    sleep 30

    # Delete service
    aws ecs delete-service --cluster "$cluster" --service "$name" --force

    log_info "ECS service deleted"
}

service_list() {
    local cluster=$1

    if [ -z "$cluster" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_info "Listing services in cluster: $cluster"
    aws ecs list-services --cluster "$cluster" --query 'serviceArns[]' --output table

    echo ""
    local services
    services=$(aws ecs list-services --cluster "$cluster" --query 'serviceArns[]' --output text)
    if [ -n "$services" ]; then
        aws ecs describe-services --cluster "$cluster" --services $services \
            --query 'services[].{Name:serviceName,Status:status,Desired:desiredCount,Running:runningCount,TaskDef:taskDefinition}' \
            --output table
    fi
}

service_update() {
    local cluster=$1
    local name=$2
    local desired_count=$3

    if [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$desired_count" ]; then
        log_error "Cluster, service name, and desired count are required"
        exit 1
    fi

    log_step "Updating ECS service: $name"
    aws ecs update-service --cluster "$cluster" --service "$name" --desired-count "$desired_count"
    log_info "ECS service updated"
}

service_logs() {
    local cluster=$1
    local name=$2

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and service name are required"
        exit 1
    fi

    log_info "Fetching logs for service: $name"
    aws logs tail "/ecs/$name" --follow
}

# ============================================
# ALB Functions
# ============================================

alb_create() {
    local name=$1
    local vpc_id=$2
    local subnet_ids=$3  # comma-separated

    if [ -z "$name" ] || [ -z "$vpc_id" ] || [ -z "$subnet_ids" ]; then
        log_error "ALB name, VPC ID, and subnet IDs are required"
        exit 1
    fi

    log_step "Creating Application Load Balancer: $name"

    # Create security group for ALB
    local alb_sg
    alb_sg=$(aws ec2 create-security-group \
        --group-name "$name-alb-sg" \
        --description "Security group for ALB $name" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress --group-id "$alb_sg" --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "$alb_sg" --protocol tcp --port 443 --cidr 0.0.0.0/0

    log_info "Created ALB security group: $alb_sg"

    # Create ALB
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "$name" \
        --subnets ${subnet_ids//,/ } \
        --security-groups "$alb_sg" \
        --scheme internet-facing \
        --type application \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)

    log_info "Created ALB: $alb_arn"

    local dns_name
    dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' --output text)

    echo ""
    echo -e "${GREEN}ALB Created Successfully${NC}"
    echo "ALB ARN: $alb_arn"
    echo "DNS Name: $dns_name"
    echo "Security Group: $alb_sg"
}

alb_delete() {
    local alb_arn=$1

    if [ -z "$alb_arn" ]; then
        log_error "ALB ARN is required"
        exit 1
    fi

    log_warn "This will delete ALB: $alb_arn"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting ALB: $alb_arn"

    # Delete listeners
    local listeners
    listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$alb_arn" --query 'Listeners[].ListenerArn' --output text)
    for listener in $listeners; do
        aws elbv2 delete-listener --listener-arn "$listener"
    done

    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn"
    log_info "ALB deleted"
}

alb_list() {
    log_info "Listing Application Load Balancers..."
    aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[?Type==`application`].{Name:LoadBalancerName,DNSName:DNSName,State:State.Code,ARN:LoadBalancerArn}' \
        --output table
}

tg_create() {
    local name=$1
    local vpc_id=$2
    local port=${3:-80}

    if [ -z "$name" ] || [ -z "$vpc_id" ]; then
        log_error "Target group name and VPC ID are required"
        exit 1
    fi

    log_step "Creating Target Group (IP type for Fargate): $name"

    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$name" \
        --protocol HTTP \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --query 'TargetGroups[0].TargetGroupArn' --output text)

    log_info "Created Target Group: $tg_arn"
    echo "$tg_arn"
}

tg_delete() {
    local tg_arn=$1

    if [ -z "$tg_arn" ]; then
        log_error "Target Group ARN is required"
        exit 1
    fi

    log_step "Deleting Target Group: $tg_arn"
    aws elbv2 delete-target-group --target-group-arn "$tg_arn"
    log_info "Target Group deleted"
}

listener_create() {
    local alb_arn=$1
    local tg_arn=$2

    if [ -z "$alb_arn" ] || [ -z "$tg_arn" ]; then
        log_error "ALB ARN and Target Group ARN are required"
        exit 1
    fi

    log_step "Creating HTTP listener"

    aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$tg_arn"

    log_info "HTTP listener created"
}

# ============================================
# Aurora Functions
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

    log_step "Deleting DB Subnet Group: $name"
    aws rds delete-db-subnet-group --db-subnet-group-name "$name"
    log_info "DB Subnet Group deleted"
}

aurora_create() {
    local cluster_id=$1
    local username=$2
    local password=$3
    local subnet_group=$4
    local sg_id=$5

    if [ -z "$cluster_id" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$subnet_group" ]; then
        log_error "Cluster ID, username, password, and subnet group are required"
        exit 1
    fi

    log_step "Creating Aurora MySQL Serverless v2 cluster: $cluster_id"

    local cluster_args="--db-cluster-identifier $cluster_id"
    cluster_args="$cluster_args --engine aurora-mysql"
    cluster_args="$cluster_args --engine-version 8.0.mysql_aurora.3.04.0"
    cluster_args="$cluster_args --master-username $username"
    cluster_args="$cluster_args --master-user-password $password"
    cluster_args="$cluster_args --db-subnet-group-name $subnet_group"
    cluster_args="$cluster_args --storage-encrypted"
    cluster_args="$cluster_args --backup-retention-period 7"
    cluster_args="$cluster_args --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16"

    if [ -n "$sg_id" ]; then
        cluster_args="$cluster_args --vpc-security-group-ids $sg_id"
    fi

    aws rds create-db-cluster $cluster_args

    log_info "Aurora cluster creation initiated"
    log_info "Creating Aurora Serverless v2 instance..."

    # Create writer instance
    aws rds create-db-instance \
        --db-instance-identifier "${cluster_id}-instance-1" \
        --db-cluster-identifier "$cluster_id" \
        --engine aurora-mysql \
        --db-instance-class db.serverless

    log_info "Aurora cluster and instance creation initiated. This may take several minutes..."
    log_info "Use 'aurora-status $cluster_id' to check the status"
}

aurora_delete() {
    local cluster_id=$1

    if [ -z "$cluster_id" ]; then
        log_error "Cluster ID is required"
        exit 1
    fi

    log_warn "This will delete Aurora cluster: $cluster_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting Aurora cluster: $cluster_id"

    # Delete instances first
    local instances
    instances=$(aws rds describe-db-instances \
        --filters "Name=db-cluster-id,Values=$cluster_id" \
        --query 'DBInstances[].DBInstanceIdentifier' --output text)

    for instance in $instances; do
        log_info "Deleting instance: $instance"
        aws rds delete-db-instance \
            --db-instance-identifier "$instance" \
            --skip-final-snapshot
    done

    log_info "Waiting for instances to be deleted..."
    for instance in $instances; do
        aws rds wait db-instance-deleted --db-instance-identifier "$instance" || true
    done

    # Delete cluster
    aws rds delete-db-cluster \
        --db-cluster-identifier "$cluster_id" \
        --skip-final-snapshot

    log_info "Aurora cluster deletion initiated"
}

aurora_list() {
    log_info "Listing Aurora clusters..."
    aws rds describe-db-clusters \
        --query 'DBClusters[].{Cluster:DBClusterIdentifier,Engine:Engine,Status:Status,Endpoint:Endpoint,ReaderEndpoint:ReaderEndpoint}' \
        --output table
}

aurora_status() {
    local cluster_id=$1

    if [ -z "$cluster_id" ]; then
        log_error "Cluster ID is required"
        exit 1
    fi

    log_info "Aurora cluster status: $cluster_id"
    aws rds describe-db-clusters \
        --db-cluster-identifier "$cluster_id" \
        --query 'DBClusters[0].{Cluster:DBClusterIdentifier,Status:Status,Engine:Engine,EngineVersion:EngineVersion,Endpoint:Endpoint,ReaderEndpoint:ReaderEndpoint,Port:Port}' \
        --output table

    echo ""
    log_info "Cluster instances:"
    aws rds describe-db-instances \
        --filters "Name=db-cluster-id,Values=$cluster_id" \
        --query 'DBInstances[].{Instance:DBInstanceIdentifier,Class:DBInstanceClass,Status:DBInstanceStatus}' \
        --output table
}

aurora_add_instance() {
    local cluster_id=$1
    local instance_id=$2

    if [ -z "$cluster_id" ] || [ -z "$instance_id" ]; then
        log_error "Cluster ID and instance ID are required"
        exit 1
    fi

    log_step "Adding instance to Aurora cluster: $cluster_id"

    aws rds create-db-instance \
        --db-instance-identifier "$instance_id" \
        --db-cluster-identifier "$cluster_id" \
        --engine aurora-mysql \
        --db-instance-class db.serverless

    log_info "Instance creation initiated"
}

# ============================================
# CloudFront Functions
# ============================================

cf_create() {
    local alb_dns=$1
    local stack_name=$2

    if [ -z "$alb_dns" ] || [ -z "$stack_name" ]; then
        log_error "ALB DNS name and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution for ALB: $alb_dns"

    local dist_config=$(cat << EOF
{
    "CallerReference": "$stack_name-$(date +%s)",
    "Comment": "CloudFront distribution for $stack_name (ECS Fargate)",
    "DefaultCacheBehavior": {
        "TargetOriginId": "ALB-$stack_name",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
        "CachedMethods": ["GET", "HEAD"],
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {"Forward": "all"},
            "Headers": ["Host", "Origin", "Authorization"]
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "ALB-$stack_name",
            "DomainName": "$alb_dns",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only",
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

    log_step "Disabling CloudFront distribution: $dist_id"

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

    log_step "Creating invalidation for: $path"
    aws cloudfront create-invalidation \
        --distribution-id "$dist_id" \
        --paths "$path"
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

    log_info "Deploying full architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets (with NAT Gateway)"
    echo "  - ECR repository"
    echo "  - ECS Fargate cluster and service"
    echo "  - Application Load Balancer"
    echo "  - Aurora MySQL Serverless v2 cluster"
    echo "  - CloudFront distribution"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Step 1/6: Creating VPC..."
    vpc_create "$stack_name"

    log_info "Please note the VPC ID and subnet IDs, then run individual commands to complete setup"
    log_info "Or use the Terraform modules in iac/environments for automated deployment"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_warn "This will destroy all resources for: $stack_name"
    echo ""
    echo "Recommended deletion order:"
    echo "  1. CloudFront distribution"
    echo "  2. ECS services"
    echo "  3. ECS cluster"
    echo "  4. Task definitions"
    echo "  5. ECR repository"
    echo "  6. ALB and Target Groups"
    echo "  7. Aurora cluster"
    echo "  8. DB Subnet Group"
    echo "  9. Security Groups"
    echo "  10. VPC (includes NAT Gateway)"
    echo ""

    log_info "Use individual delete commands with resource IDs"
}

status() {
    local stack_name=$1

    log_info "Checking status for stack: $stack_name"
    echo ""

    echo -e "${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list

    echo -e "\n${BLUE}=== Application Load Balancers ===${NC}"
    alb_list

    echo -e "\n${BLUE}=== ECS Clusters ===${NC}"
    cluster_list

    echo -e "\n${BLUE}=== Aurora Clusters ===${NC}"
    aurora_list

    echo -e "\n${BLUE}=== ECR Repositories ===${NC}"
    ecr_list

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
    deploy)
        deploy "$@"
        ;;
    destroy)
        destroy "$@"
        ;;
    status)
        status "$@"
        ;;

    # VPC
    vpc-create)
        vpc_create "$@"
        ;;
    vpc-delete)
        vpc_delete "$@"
        ;;
    vpc-list)
        vpc_list
        ;;
    sg-create)
        sg_create "$@"
        ;;
    sg-delete)
        sg_delete "$@"
        ;;

    # ECR
    ecr-create)
        ecr_create "$@"
        ;;
    ecr-delete)
        ecr_delete "$@"
        ;;
    ecr-list)
        ecr_list
        ;;
    ecr-login)
        ecr_login
        ;;
    ecr-push)
        ecr_push "$@"
        ;;

    # ECS Cluster
    cluster-create)
        cluster_create "$@"
        ;;
    cluster-delete)
        cluster_delete "$@"
        ;;
    cluster-list)
        cluster_list
        ;;

    # ECS Task Definition
    task-def-create)
        task_def_create "$@"
        ;;
    task-def-delete)
        task_def_delete "$@"
        ;;
    task-def-list)
        task_def_list
        ;;

    # ECS Service
    service-create)
        service_create "$@"
        ;;
    service-delete)
        service_delete "$@"
        ;;
    service-list)
        service_list "$@"
        ;;
    service-update)
        service_update "$@"
        ;;
    service-logs)
        service_logs "$@"
        ;;

    # ALB
    alb-create)
        alb_create "$@"
        ;;
    alb-delete)
        alb_delete "$@"
        ;;
    alb-list)
        alb_list
        ;;
    tg-create)
        tg_create "$@"
        ;;
    tg-delete)
        tg_delete "$@"
        ;;
    listener-create)
        listener_create "$@"
        ;;

    # Aurora
    aurora-create)
        aurora_create "$@"
        ;;
    aurora-delete)
        aurora_delete "$@"
        ;;
    aurora-list)
        aurora_list
        ;;
    aurora-status)
        aurora_status "$@"
        ;;
    aurora-add-instance)
        aurora_add_instance "$@"
        ;;
    subnet-group-create)
        subnet_group_create "$@"
        ;;
    subnet-group-delete)
        subnet_group_delete "$@"
        ;;

    # CloudFront
    cf-create)
        cf_create "$@"
        ;;
    cf-delete)
        cf_delete "$@"
        ;;
    cf-list)
        cf_list
        ;;
    cf-invalidate)
        cf_invalidate "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
