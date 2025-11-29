#!/bin/bash
# =============================================================================
# ECR -> ECS Fargate Architecture Script
# =============================================================================
# This script creates and manages the following architecture:
#   - VPC with public and private subnets (2 AZs)
#   - Internet Gateway and NAT Gateway
#   - ECR repository for container images
#   - ECS Fargate cluster and service
#   - Application Load Balancer
#   - Security Groups
#
# Usage: ./script.sh <command> [options]
# =============================================================================

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# =============================================================================
# Default Configuration
# =============================================================================
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_FARGATE_CPU="256"
DEFAULT_FARGATE_MEMORY="512"
DEFAULT_DESIRED_COUNT=2
DEFAULT_CONTAINER_PORT=80

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "ECR -> ECS Fargate Architecture"
    echo ""
    echo "  VPC with public/private subnets -> ALB -> ECS Fargate -> ECR"
    echo ""
    echo "Commands:"
    echo ""
    echo "  === Full Stack ==="
    echo "  deploy <stack-name>                    - Deploy the full architecture"
    echo "  destroy <stack-name>                   - Destroy the full architecture"
    echo "  status [stack-name]                    - Show status of all components"
    echo ""
    echo "  === VPC ==="
    echo "  vpc-create <name> [cidr]               - Create VPC with subnets (default: 10.0.0.0/16)"
    echo "  vpc-list                               - List all VPCs"
    echo "  vpc-show <vpc-id>                      - Show VPC details"
    echo "  vpc-delete <vpc-id>                    - Delete VPC and all associated resources"
    echo ""
    echo "  === ECR ==="
    echo "  ecr-create <repo-name>                 - Create ECR repository"
    echo "  ecr-list                               - List ECR repositories"
    echo "  ecr-delete <repo-name>                 - Delete ECR repository"
    echo "  ecr-login                              - Login to ECR (docker)"
    echo "  ecr-push <repo-name> <image:tag>       - Tag and push image to ECR"
    echo "  ecr-images <repo-name>                 - List images in repository"
    echo ""
    echo "  === ECS Cluster ==="
    echo "  cluster-create <name>                  - Create ECS cluster"
    echo "  cluster-list                           - List ECS clusters"
    echo "  cluster-delete <name>                  - Delete ECS cluster"
    echo ""
    echo "  === Task Definition ==="
    echo "  task-create <family> <image> [port] [cpu] [memory]"
    echo "                                         - Create task definition"
    echo "  task-list                              - List task definitions"
    echo "  task-show <family>                     - Show task definition details"
    echo "  task-delete <family>                   - Deregister all revisions"
    echo ""
    echo "  === ECS Service ==="
    echo "  service-create <cluster> <name> <task-def> <subnets> <sg-id> [tg-arn]"
    echo "                                         - Create ECS service"
    echo "  service-list <cluster>                 - List services in cluster"
    echo "  service-show <cluster> <name>          - Show service details"
    echo "  service-update <cluster> <name> <task-def> [count]"
    echo "                                         - Update service"
    echo "  service-delete <cluster> <name>        - Delete service"
    echo ""
    echo "  === Application Load Balancer ==="
    echo "  alb-create <name> <vpc-id> <subnet-ids> - Create ALB (comma-separated subnets)"
    echo "  alb-list                               - List ALBs"
    echo "  alb-delete <alb-arn>                   - Delete ALB"
    echo "  tg-create <name> <vpc-id> [port]       - Create target group"
    echo "  tg-list                                - List target groups"
    echo "  tg-delete <tg-arn>                     - Delete target group"
    echo "  listener-create <alb-arn> <tg-arn>     - Create HTTP listener"
    echo "  listener-delete <listener-arn>         - Delete listener"
    echo ""
    echo "  === Security Groups ==="
    echo "  sg-create-alb <name> <vpc-id>          - Create ALB security group"
    echo "  sg-create-ecs <name> <vpc-id> <alb-sg-id>"
    echo "                                         - Create ECS security group"
    echo "  sg-list <vpc-id>                       - List security groups in VPC"
    echo "  sg-delete <sg-id>                      - Delete security group"
    echo ""
    echo "  === IAM ==="
    echo "  iam-create-task-role <name>            - Create ECS task execution role"
    echo "  iam-delete-task-role <name>            - Delete ECS task execution role"
    echo ""
    echo "Examples:"
    echo "  # Deploy full stack"
    echo "  $0 deploy my-app"
    echo ""
    echo "  # Manual step-by-step deployment"
    echo "  $0 vpc-create my-app"
    echo "  $0 ecr-create my-app"
    echo "  $0 ecr-login"
    echo "  $0 ecr-push my-app my-image:latest"
    echo "  $0 cluster-create my-app"
    echo "  $0 task-create my-app <account>.dkr.ecr.<region>.amazonaws.com/my-app:latest"
    echo "  $0 alb-create my-app <vpc-id> <subnet-1>,<subnet-2>"
    echo "  $0 tg-create my-app <vpc-id>"
    echo "  $0 listener-create <alb-arn> <tg-arn>"
    echo "  $0 service-create my-app my-app-svc my-app <subnet-ids> <sg-id> <tg-arn>"
    echo ""
    exit 1
}

# =============================================================================
# VPC Functions
# =============================================================================
vpc_create() {
    local name=$1
    local cidr=${2:-$DEFAULT_VPC_CIDR}

    require_param "$name" "VPC name"

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
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support
    log_info "Enabled DNS hostnames and DNS support"

    # Create Internet Gateway
    log_step "Creating Internet Gateway..."
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$name-igw}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 attach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
    log_info "Created and attached Internet Gateway: $igw_id"

    # Get availability zones
    local azs
    azs=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[?State==`available`].ZoneName' --output text | head -2 | tr '\t' ' ')
    local az_array=($azs)

    if [ ${#az_array[@]} -lt 2 ]; then
        log_error "Need at least 2 availability zones"
        exit 1
    fi

    log_info "Using availability zones: ${az_array[0]}, ${az_array[1]}"

    # Create public subnets
    log_step "Creating public subnets..."
    local public_subnet_1
    public_subnet_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.1.0/24" \
        --availability-zone "${az_array[0]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-1}]" \
        --query 'Subnet.SubnetId' --output text)
    log_info "Created public subnet 1: $public_subnet_1"

    local public_subnet_2
    public_subnet_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.2.0/24" \
        --availability-zone "${az_array[1]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-2}]" \
        --query 'Subnet.SubnetId' --output text)
    log_info "Created public subnet 2: $public_subnet_2"

    # Create private subnets
    log_step "Creating private subnets..."
    local private_subnet_1
    private_subnet_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.11.0/24" \
        --availability-zone "${az_array[0]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-1}]" \
        --query 'Subnet.SubnetId' --output text)
    log_info "Created private subnet 1: $private_subnet_1"

    local private_subnet_2
    private_subnet_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.12.0/24" \
        --availability-zone "${az_array[1]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-2}]" \
        --query 'Subnet.SubnetId' --output text)
    log_info "Created private subnet 2: $private_subnet_2"

    # Create public route table
    log_step "Creating route tables..."
    local public_rt
    public_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-public-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route \
        --route-table-id "$public_rt" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id" > /dev/null

    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_1" > /dev/null
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_2" > /dev/null
    log_info "Created public route table: $public_rt"

    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_1" --map-public-ip-on-launch
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_2" --map-public-ip-on-launch

    # Create NAT Gateway
    log_step "Creating NAT Gateway (this may take a few minutes)..."
    local eip_alloc
    eip_alloc=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$name-nat-eip}]" \
        --query 'AllocationId' --output text)
    log_info "Allocated Elastic IP: $eip_alloc"

    local nat_gw
    nat_gw=$(aws ec2 create-nat-gateway \
        --subnet-id "$public_subnet_1" \
        --allocation-id "$eip_alloc" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$name-nat}]" \
        --query 'NatGateway.NatGatewayId' --output text)
    log_info "Created NAT Gateway: $nat_gw (waiting for availability...)"

    aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat_gw"
    log_info "NAT Gateway is now available"

    # Create private route table
    local private_rt
    private_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-private-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route \
        --route-table-id "$private_rt" \
        --destination-cidr-block "0.0.0.0/0" \
        --nat-gateway-id "$nat_gw" > /dev/null

    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet_1" > /dev/null
    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet_2" > /dev/null
    log_info "Created private route table: $private_rt"

    log_success "VPC created successfully!"
    echo ""
    echo -e "${GREEN}=== VPC Summary ===${NC}"
    echo "VPC ID:            $vpc_id"
    echo "VPC CIDR:          $cidr"
    echo "Internet Gateway:  $igw_id"
    echo "NAT Gateway:       $nat_gw"
    echo "Public Subnets:    $public_subnet_1, $public_subnet_2"
    echo "Private Subnets:   $private_subnet_1, $private_subnet_2"
    echo ""
    echo "Use public subnets for ALB, private subnets for ECS tasks"
}

vpc_list() {
    log_step "Listing VPCs..."
    aws ec2 describe-vpcs \
        --query 'Vpcs[*].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],State:State}' \
        --output table
}

vpc_show() {
    local vpc_id=$1
    require_param "$vpc_id" "VPC ID"

    log_step "Showing VPC details: $vpc_id"

    echo -e "\n${BLUE}=== VPC ===${NC}"
    aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],State:State}' \
        --output table

    echo -e "\n${BLUE}=== Subnets ===${NC}"
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AZ:AvailabilityZone,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output table

    echo -e "\n${BLUE}=== Internet Gateways ===${NC}"
    aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[*].{IGWId:InternetGatewayId,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output table

    echo -e "\n${BLUE}=== NAT Gateways ===${NC}"
    aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NatGateways[?State!=`deleted`].{NatGwId:NatGatewayId,State:State,SubnetId:SubnetId,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output table

    echo -e "\n${BLUE}=== Security Groups ===${NC}"
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,Description:Description}' \
        --output table
}

vpc_delete() {
    local vpc_id=$1
    require_param "$vpc_id" "VPC ID"

    confirm_action "This will delete VPC $vpc_id and ALL associated resources (NAT Gateway, subnets, etc.)"

    log_step "Deleting VPC: $vpc_id"

    # Delete NAT Gateways
    log_info "Deleting NAT Gateways..."
    local nat_gws=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text)
    for nat_gw in $nat_gws; do
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_gw"
        log_info "Deleting NAT Gateway: $nat_gw"
    done

    # Wait for NAT Gateway deletion
    if [ -n "$nat_gws" ]; then
        log_info "Waiting for NAT Gateway deletion..."
        for nat_gw in $nat_gws; do
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat_gw" 2>/dev/null || true
        done
    fi

    # Release Elastic IPs
    log_info "Releasing Elastic IPs..."
    local eips=$(aws ec2 describe-addresses \
        --filters "Name=domain,Values=vpc" \
        --query "Addresses[?NetworkInterfaceId==null].AllocationId" --output text)
    for eip in $eips; do
        aws ec2 release-address --allocation-id "$eip" 2>/dev/null || true
    done

    # Delete subnets
    log_info "Deleting subnets..."
    local subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].SubnetId' --output text)
    for subnet in $subnets; do
        aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
        log_info "Deleted subnet: $subnet"
    done

    # Delete route tables (except main)
    log_info "Deleting route tables..."
    local route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for rt in $route_tables; do
        # Delete associations first
        local associations=$(aws ec2 describe-route-tables \
            --route-table-ids "$rt" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text)
        for assoc in $associations; do
            aws ec2 disassociate-route-table --association-id "$assoc" 2>/dev/null || true
        done
        aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
        log_info "Deleted route table: $rt"
    done

    # Detach and delete Internet Gateway
    log_info "Deleting Internet Gateway..."
    local igws=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[*].InternetGatewayId' --output text)
    for igw in $igws; do
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
        log_info "Deleted Internet Gateway: $igw"
    done

    # Delete security groups (except default)
    log_info "Deleting security groups..."
    local sgs=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for sg in $sgs; do
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
        log_info "Deleted security group: $sg"
    done

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_success "Deleted VPC: $vpc_id"
}

# =============================================================================
# ECR Functions
# =============================================================================
ecr_create() {
    local repo_name=$1
    require_param "$repo_name" "Repository name"

    log_step "Creating ECR repository: $repo_name"

    local repo_uri
    repo_uri=$(aws ecr create-repository \
        --repository-name "$repo_name" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --query 'repository.repositoryUri' --output text)

    log_success "Created ECR repository: $repo_uri"
    echo ""
    echo "Repository URI: $repo_uri"
    echo ""
    echo "To push an image:"
    echo "  $0 ecr-login"
    echo "  docker tag <image>:tag $repo_uri:tag"
    echo "  docker push $repo_uri:tag"
}

ecr_list() {
    log_step "Listing ECR repositories..."
    aws ecr describe-repositories \
        --query 'repositories[*].{Name:repositoryName,URI:repositoryUri,CreatedAt:createdAt}' \
        --output table
}

ecr_delete() {
    local repo_name=$1
    require_param "$repo_name" "Repository name"

    confirm_action "This will delete ECR repository '$repo_name' and all images"

    log_step "Deleting ECR repository: $repo_name"
    aws ecr delete-repository --repository-name "$repo_name" --force
    log_success "Deleted ECR repository: $repo_name"
}

ecr_login() {
    log_step "Logging in to ECR..."
    local account_id=$(get_account_id)
    local region=$(get_region)

    aws ecr get-login-password --region "$region" | \
        docker login --username AWS --password-stdin "$account_id.dkr.ecr.$region.amazonaws.com"

    log_success "Successfully logged in to ECR"
}

ecr_push() {
    local repo_name=$1
    local image_tag=$2
    require_param "$repo_name" "Repository name"
    require_param "$image_tag" "Image:tag"

    local account_id=$(get_account_id)
    local region=$(get_region)
    local repo_uri="$account_id.dkr.ecr.$region.amazonaws.com/$repo_name"

    log_step "Tagging image: $image_tag -> $repo_uri:latest"
    docker tag "$image_tag" "$repo_uri:latest"

    log_step "Pushing image to ECR..."
    docker push "$repo_uri:latest"

    log_success "Image pushed successfully"
    echo "Image URI: $repo_uri:latest"
}

ecr_images() {
    local repo_name=$1
    require_param "$repo_name" "Repository name"

    log_step "Listing images in repository: $repo_name"
    aws ecr describe-images \
        --repository-name "$repo_name" \
        --query 'imageDetails[*].{Tags:imageTags[0],Digest:imageDigest,Size:imageSizeInBytes,PushedAt:imagePushedAt}' \
        --output table
}

# =============================================================================
# ECS Cluster Functions
# =============================================================================
cluster_create() {
    local name=$1
    require_param "$name" "Cluster name"

    log_step "Creating ECS cluster: $name"

    aws ecs create-cluster \
        --cluster-name "$name" \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --settings name=containerInsights,value=enabled \
        --query 'cluster.{Name:clusterName,Status:status,ARN:clusterArn}' \
        --output table

    log_success "Created ECS cluster: $name"
}

cluster_list() {
    log_step "Listing ECS clusters..."
    local clusters=$(aws ecs list-clusters --query 'clusterArns' --output text)

    if [ -z "$clusters" ]; then
        echo "No clusters found"
        return
    fi

    aws ecs describe-clusters \
        --clusters $clusters \
        --query 'clusters[*].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,Services:activeServicesCount}' \
        --output table
}

cluster_delete() {
    local name=$1
    require_param "$name" "Cluster name"

    confirm_action "This will delete ECS cluster '$name'"

    log_step "Deleting ECS cluster: $name"
    aws ecs delete-cluster --cluster "$name"
    log_success "Deleted ECS cluster: $name"
}

# =============================================================================
# Task Definition Functions
# =============================================================================
task_create() {
    local family=$1
    local image=$2
    local port=${3:-$DEFAULT_CONTAINER_PORT}
    local cpu=${4:-$DEFAULT_FARGATE_CPU}
    local memory=${5:-$DEFAULT_FARGATE_MEMORY}

    require_param "$family" "Task family name"
    require_param "$image" "Container image"

    log_step "Creating task definition: $family"

    local account_id=$(get_account_id)
    local region=$(get_region)
    local execution_role_arn="arn:aws:iam::$account_id:role/ecsTaskExecutionRole"

    # Check if ecsTaskExecutionRole exists, create if not
    if ! aws iam get-role --role-name ecsTaskExecutionRole &>/dev/null; then
        log_info "Creating ecsTaskExecutionRole..."
        iam_create_task_role "ecsTaskExecutionRole"
    fi

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
                    "awslogs-region": "$region",
                    "awslogs-stream-prefix": "ecs",
                    "awslogs-create-group": "true"
                }
            }
        }
    ]
}
EOF
)

    aws ecs register-task-definition --cli-input-json "$task_def" \
        --query 'taskDefinition.{Family:family,Revision:revision,Status:status,CPU:cpu,Memory:memory}' \
        --output table

    log_success "Created task definition: $family"
}

task_list() {
    log_step "Listing task definitions..."
    aws ecs list-task-definition-families \
        --status ACTIVE \
        --query 'families' \
        --output table
}

task_show() {
    local family=$1
    require_param "$family" "Task family name"

    log_step "Showing task definition: $family"
    aws ecs describe-task-definition \
        --task-definition "$family" \
        --query 'taskDefinition.{Family:family,Revision:revision,Status:status,CPU:cpu,Memory:memory,Image:containerDefinitions[0].image,Port:containerDefinitions[0].portMappings[0].containerPort}' \
        --output table
}

task_delete() {
    local family=$1
    require_param "$family" "Task family name"

    confirm_action "This will deregister all revisions of task definition '$family'"

    log_step "Deregistering task definitions: $family"

    local arns=$(aws ecs list-task-definitions \
        --family-prefix "$family" \
        --query 'taskDefinitionArns' --output text)

    for arn in $arns; do
        aws ecs deregister-task-definition --task-definition "$arn" > /dev/null
        log_info "Deregistered: $arn"
    done

    log_success "Deregistered all task definitions for: $family"
}

# =============================================================================
# ECS Service Functions
# =============================================================================
service_create() {
    local cluster=$1
    local name=$2
    local task_def=$3
    local subnet_ids=$4
    local sg_id=$5
    local tg_arn=$6

    require_param "$cluster" "Cluster name"
    require_param "$name" "Service name"
    require_param "$task_def" "Task definition"
    require_param "$subnet_ids" "Subnet IDs (comma-separated)"
    require_param "$sg_id" "Security group ID"

    log_step "Creating ECS service: $name"

    # Convert comma-separated subnets to JSON array
    local subnets_json=$(echo "$subnet_ids" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd,)
    local network_config="{\"awsvpcConfiguration\":{\"subnets\":[$subnets_json],\"securityGroups\":[\"$sg_id\"],\"assignPublicIp\":\"DISABLED\"}}"

    local create_args="--cluster $cluster"
    create_args="$create_args --service-name $name"
    create_args="$create_args --task-definition $task_def"
    create_args="$create_args --desired-count $DEFAULT_DESIRED_COUNT"
    create_args="$create_args --launch-type FARGATE"
    create_args="$create_args --platform-version LATEST"
    create_args="$create_args --network-configuration $network_config"

    # Add load balancer if target group is provided
    if [ -n "$tg_arn" ]; then
        local container_name=$(aws ecs describe-task-definition \
            --task-definition "$task_def" \
            --query 'taskDefinition.containerDefinitions[0].name' --output text)
        local container_port=$(aws ecs describe-task-definition \
            --task-definition "$task_def" \
            --query 'taskDefinition.containerDefinitions[0].portMappings[0].containerPort' --output text)

        local lb_config="[{\"targetGroupArn\":\"$tg_arn\",\"containerName\":\"$container_name\",\"containerPort\":$container_port}]"
        create_args="$create_args --load-balancers $lb_config"
    fi

    aws ecs create-service $create_args \
        --query 'service.{Name:serviceName,Status:status,DesiredCount:desiredCount,RunningCount:runningCount}' \
        --output table

    log_success "Created ECS service: $name"
}

service_list() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Listing services in cluster: $cluster"
    local services=$(aws ecs list-services --cluster "$cluster" --query 'serviceArns' --output text)

    if [ -z "$services" ]; then
        echo "No services found in cluster $cluster"
        return
    fi

    aws ecs describe-services \
        --cluster "$cluster" \
        --services $services \
        --query 'services[*].{Name:serviceName,Status:status,Desired:desiredCount,Running:runningCount,TaskDef:taskDefinition}' \
        --output table
}

service_show() {
    local cluster=$1
    local name=$2
    require_param "$cluster" "Cluster name"
    require_param "$name" "Service name"

    log_step "Showing service: $name"
    aws ecs describe-services \
        --cluster "$cluster" \
        --services "$name" \
        --query 'services[0]' \
        --output yaml
}

service_update() {
    local cluster=$1
    local name=$2
    local task_def=$3
    local count=${4:-$DEFAULT_DESIRED_COUNT}

    require_param "$cluster" "Cluster name"
    require_param "$name" "Service name"
    require_param "$task_def" "Task definition"

    log_step "Updating service: $name"

    aws ecs update-service \
        --cluster "$cluster" \
        --service "$name" \
        --task-definition "$task_def" \
        --desired-count "$count" \
        --query 'service.{Name:serviceName,Status:status,DesiredCount:desiredCount,TaskDef:taskDefinition}' \
        --output table

    log_success "Updated service: $name"
}

service_delete() {
    local cluster=$1
    local name=$2
    require_param "$cluster" "Cluster name"
    require_param "$name" "Service name"

    confirm_action "This will delete ECS service '$name'"

    log_step "Scaling service to 0..."
    aws ecs update-service --cluster "$cluster" --service "$name" --desired-count 0 > /dev/null

    log_step "Deleting service: $name"
    aws ecs delete-service --cluster "$cluster" --service "$name"
    log_success "Deleted service: $name"
}

# =============================================================================
# ALB Functions
# =============================================================================
alb_create() {
    local name=$1
    local vpc_id=$2
    local subnet_ids=$3

    require_param "$name" "ALB name"
    require_param "$vpc_id" "VPC ID"
    require_param "$subnet_ids" "Subnet IDs (comma-separated)"

    log_step "Creating Application Load Balancer: $name"

    # Create security group for ALB
    log_info "Creating ALB security group..."
    local alb_sg
    alb_sg=$(aws ec2 create-security-group \
        --group-name "$name-alb-sg" \
        --description "Security group for ALB $name" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress \
        --group-id "$alb_sg" \
        --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null

    aws ec2 authorize-security-group-ingress \
        --group-id "$alb_sg" \
        --protocol tcp --port 443 --cidr 0.0.0.0/0 > /dev/null

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

    local dns_name
    dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' --output text)

    log_success "Created ALB: $name"
    echo ""
    echo -e "${GREEN}=== ALB Summary ===${NC}"
    echo "ALB ARN:        $alb_arn"
    echo "DNS Name:       $dns_name"
    echo "Security Group: $alb_sg"
    echo ""
    echo "Next steps:"
    echo "  1. Create target group: $0 tg-create $name-tg $vpc_id"
    echo "  2. Create listener: $0 listener-create <alb-arn> <tg-arn>"
}

alb_list() {
    log_step "Listing Application Load Balancers..."
    aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[?Type==`application`].{Name:LoadBalancerName,DNSName:DNSName,State:State.Code,ARN:LoadBalancerArn}' \
        --output table
}

alb_delete() {
    local alb_arn=$1
    require_param "$alb_arn" "ALB ARN"

    confirm_action "This will delete the ALB"

    log_step "Deleting listeners..."
    local listeners=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --query 'Listeners[*].ListenerArn' --output text)
    for listener in $listeners; do
        aws elbv2 delete-listener --listener-arn "$listener"
        log_info "Deleted listener: $listener"
    done

    log_step "Deleting ALB..."
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn"
    log_success "Deleted ALB"
}

tg_create() {
    local name=$1
    local vpc_id=$2
    local port=${3:-$DEFAULT_CONTAINER_PORT}

    require_param "$name" "Target group name"
    require_param "$vpc_id" "VPC ID"

    log_step "Creating target group: $name"

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

    log_success "Created target group: $name"
    echo "Target Group ARN: $tg_arn"
}

tg_list() {
    log_step "Listing target groups..."
    aws elbv2 describe-target-groups \
        --query 'TargetGroups[*].{Name:TargetGroupName,Port:Port,Protocol:Protocol,TargetType:TargetType,ARN:TargetGroupArn}' \
        --output table
}

tg_delete() {
    local tg_arn=$1
    require_param "$tg_arn" "Target group ARN"

    confirm_action "This will delete the target group"

    log_step "Deleting target group..."
    aws elbv2 delete-target-group --target-group-arn "$tg_arn"
    log_success "Deleted target group"
}

listener_create() {
    local alb_arn=$1
    local tg_arn=$2

    require_param "$alb_arn" "ALB ARN"
    require_param "$tg_arn" "Target group ARN"

    log_step "Creating HTTP listener..."

    local listener_arn
    listener_arn=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$tg_arn" \
        --query 'Listeners[0].ListenerArn' --output text)

    log_success "Created listener"
    echo "Listener ARN: $listener_arn"
}

listener_delete() {
    local listener_arn=$1
    require_param "$listener_arn" "Listener ARN"

    log_step "Deleting listener..."
    aws elbv2 delete-listener --listener-arn "$listener_arn"
    log_success "Deleted listener"
}

# =============================================================================
# Security Group Functions
# =============================================================================
sg_create_alb() {
    local name=$1
    local vpc_id=$2

    require_param "$name" "Security group name"
    require_param "$vpc_id" "VPC ID"

    log_step "Creating ALB security group: $name"

    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "ALB security group - allows HTTP/HTTPS from anywhere" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp --port 443 --cidr 0.0.0.0/0 > /dev/null

    aws ec2 create-tags --resources "$sg_id" --tags "Key=Name,Value=$name"

    log_success "Created ALB security group: $sg_id"
    echo "Security Group ID: $sg_id"
}

sg_create_ecs() {
    local name=$1
    local vpc_id=$2
    local alb_sg_id=$3

    require_param "$name" "Security group name"
    require_param "$vpc_id" "VPC ID"
    require_param "$alb_sg_id" "ALB security group ID"

    log_step "Creating ECS security group: $name"

    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "ECS security group - allows traffic from ALB only" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' --output text)

    # Allow traffic from ALB security group
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 0-65535 \
        --source-group "$alb_sg_id" > /dev/null

    aws ec2 create-tags --resources "$sg_id" --tags "Key=Name,Value=$name"

    log_success "Created ECS security group: $sg_id"
    echo "Security Group ID: $sg_id"
}

sg_list() {
    local vpc_id=$1
    require_param "$vpc_id" "VPC ID"

    log_step "Listing security groups in VPC: $vpc_id"
    aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[*].{GroupId:GroupId,Name:GroupName,Description:Description}' \
        --output table
}

sg_delete() {
    local sg_id=$1
    require_param "$sg_id" "Security group ID"

    confirm_action "This will delete security group $sg_id"

    log_step "Deleting security group: $sg_id"
    aws ec2 delete-security-group --group-id "$sg_id"
    log_success "Deleted security group: $sg_id"
}

# =============================================================================
# IAM Functions
# =============================================================================
iam_create_task_role() {
    local role_name=${1:-ecsTaskExecutionRole}

    log_step "Creating ECS task execution role: $role_name"

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ecs-tasks.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

    # Add CloudWatch Logs permissions
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess 2>/dev/null || true

    log_success "Created ECS task execution role: $role_name"
}

iam_delete_task_role() {
    local role_name=${1:-ecsTaskExecutionRole}

    confirm_action "This will delete IAM role '$role_name'"

    log_step "Deleting ECS task execution role: $role_name"
    delete_role_with_policies "$role_name"
    log_success "Deleted role: $role_name"
}

# =============================================================================
# Full Stack Orchestration
# =============================================================================
deploy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_info "Deploying ECR -> ECS architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets (2 AZs)"
    echo "  - Internet Gateway and NAT Gateway"
    echo "  - ECR repository"
    echo "  - ECS Fargate cluster"
    echo "  - Application Load Balancer"
    echo "  - Target Group and Listener"
    echo "  - Security Groups (ALB and ECS)"
    echo "  - ECS Task Execution Role"
    echo ""
    echo -e "${YELLOW}Note: You'll need to push a container image to ECR before the service can start${NC}"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    log_step "Step 1/7: Creating IAM role..."
    iam_create_task_role "ecsTaskExecutionRole"
    sleep 5

    log_step "Step 2/7: Creating VPC..."
    vpc_create "$stack_name"
    echo ""

    # Get VPC info
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' --output text)

    local public_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=*public*" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

    local private_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=*private*" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

    log_step "Step 3/7: Creating ECR repository..."
    ecr_create "$stack_name"
    echo ""

    log_step "Step 4/7: Creating ECS cluster..."
    cluster_create "$stack_name"
    echo ""

    log_step "Step 5/7: Creating security groups..."
    local alb_sg=$(sg_create_alb "$stack_name-alb-sg" "$vpc_id" | grep "Security Group ID:" | awk '{print $4}')
    local ecs_sg=$(sg_create_ecs "$stack_name-ecs-sg" "$vpc_id" "$alb_sg" | grep "Security Group ID:" | awk '{print $4}')
    echo ""

    log_step "Step 6/7: Creating ALB and target group..."
    # Create ALB
    local alb_arn=$(aws elbv2 create-load-balancer \
        --name "$stack_name-alb" \
        --subnets ${public_subnets//,/ } \
        --security-groups "$alb_sg" \
        --scheme internet-facing \
        --type application \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)

    local dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' --output text)
    log_info "Created ALB: $alb_arn"

    # Create target group
    local tg_arn=$(aws elbv2 create-target-group \
        --name "$stack_name-tg" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$vpc_id" \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    log_info "Created target group: $tg_arn"

    # Create listener
    aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$tg_arn" > /dev/null
    log_info "Created HTTP listener"
    echo ""

    log_step "Step 7/7: Creating task definition placeholder..."
    local account_id=$(get_account_id)
    local region=$(get_region)
    local repo_uri="$account_id.dkr.ecr.$region.amazonaws.com/$stack_name"

    # Create task definition with placeholder image
    task_create "$stack_name" "$repo_uri:latest" 80
    echo ""

    log_success "Deployment complete!"
    echo ""
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo "Stack Name:       $stack_name"
    echo "VPC ID:           $vpc_id"
    echo "ALB DNS:          http://$dns_name"
    echo "ECR Repository:   $repo_uri"
    echo "ECS Cluster:      $stack_name"
    echo "Task Definition:  $stack_name"
    echo ""
    echo -e "${YELLOW}=== Next Steps ===${NC}"
    echo "1. Build and push your container image:"
    echo "   $0 ecr-login"
    echo "   docker build -t $stack_name:latest ."
    echo "   docker tag $stack_name:latest $repo_uri:latest"
    echo "   docker push $repo_uri:latest"
    echo ""
    echo "2. Create ECS service:"
    echo "   $0 service-create $stack_name $stack_name-svc $stack_name $private_subnets $ecs_sg $tg_arn"
    echo ""
    echo "3. Access your application:"
    echo "   http://$dns_name"
}

destroy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_warn "This will destroy all resources for: $stack_name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - ECS services"
    echo "  - ECS cluster"
    echo "  - Task definitions"
    echo "  - Application Load Balancer"
    echo "  - Target groups"
    echo "  - ECR repository (and all images)"
    echo "  - Security groups"
    echo "  - VPC (NAT Gateway, subnets, etc.)"
    echo "  - CloudWatch log groups"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""

    # Get VPC ID
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

    # Delete ECS services
    log_step "Deleting ECS services..."
    local services=$(aws ecs list-services --cluster "$stack_name" --query 'serviceArns' --output text 2>/dev/null)
    for service in $services; do
        local service_name=$(echo "$service" | rev | cut -d'/' -f1 | rev)
        aws ecs update-service --cluster "$stack_name" --service "$service_name" --desired-count 0 > /dev/null 2>&1 || true
        aws ecs delete-service --cluster "$stack_name" --service "$service_name" > /dev/null 2>&1 || true
        log_info "Deleted service: $service_name"
    done

    # Delete ECS cluster
    log_step "Deleting ECS cluster..."
    aws ecs delete-cluster --cluster "$stack_name" > /dev/null 2>&1 || true
    log_info "Deleted cluster: $stack_name"

    # Deregister task definitions
    log_step "Deregistering task definitions..."
    local task_arns=$(aws ecs list-task-definitions --family-prefix "$stack_name" --query 'taskDefinitionArns' --output text 2>/dev/null)
    for task_arn in $task_arns; do
        aws ecs deregister-task-definition --task-definition "$task_arn" > /dev/null 2>&1 || true
        log_info "Deregistered: $task_arn"
    done

    # Delete ALB listeners first
    log_step "Deleting ALB listeners..."
    local alb_arn=$(aws elbv2 describe-load-balancers \
        --names "$stack_name-alb" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
    if [ -n "$alb_arn" ] && [ "$alb_arn" != "None" ]; then
        local listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$alb_arn" --query 'Listeners[*].ListenerArn' --output text 2>/dev/null)
        for listener in $listeners; do
            aws elbv2 delete-listener --listener-arn "$listener" 2>/dev/null || true
            log_info "Deleted listener"
        done
    fi

    # Delete ALB
    log_step "Deleting ALB..."
    if [ -n "$alb_arn" ] && [ "$alb_arn" != "None" ]; then
        aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" 2>/dev/null || true
        log_info "Deleted ALB: $stack_name-alb"
        sleep 10  # Wait for ALB to be deleted
    fi

    # Delete target groups
    log_step "Deleting target groups..."
    local tg_arn=$(aws elbv2 describe-target-groups \
        --names "$stack_name-tg" \
        --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
    if [ -n "$tg_arn" ] && [ "$tg_arn" != "None" ]; then
        aws elbv2 delete-target-group --target-group-arn "$tg_arn" 2>/dev/null || true
        log_info "Deleted target group: $stack_name-tg"
    fi

    # Delete ECR repository
    log_step "Deleting ECR repository..."
    aws ecr delete-repository --repository-name "$stack_name" --force > /dev/null 2>&1 || true
    log_info "Deleted ECR repository: $stack_name"

    # Delete security groups
    log_step "Deleting security groups..."
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        sleep 5  # Wait for dependencies to be released
        local sgs=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=$stack_name*" \
            --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null)
        for sg in $sgs; do
            aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
            log_info "Deleted security group: $sg"
        done
    fi

    # Delete VPC
    log_step "Deleting VPC..."
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        vpc_delete "$vpc_id" <<< "yes" 2>/dev/null || true
    fi

    # Delete CloudWatch log groups
    log_step "Deleting CloudWatch log groups..."
    aws logs delete-log-group --log-group-name "/ecs/$stack_name" 2>/dev/null || true
    log_info "Deleted log group: /ecs/$stack_name"

    log_success "Destroyed all resources for: $stack_name"
}

status() {
    local stack_name=${1:-}

    log_info "Checking status${stack_name:+ for stack: $stack_name}..."
    echo ""

    echo -e "${BLUE}=== VPCs ===${NC}"
    if [ -n "$stack_name" ]; then
        aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=$stack_name" \
            --query 'Vpcs[*].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],State:State}' \
            --output table 2>/dev/null || echo "No VPCs found"
    else
        vpc_list
    fi

    echo -e "\n${BLUE}=== ECR Repositories ===${NC}"
    if [ -n "$stack_name" ]; then
        aws ecr describe-repositories \
            --repository-names "$stack_name" \
            --query 'repositories[*].{Name:repositoryName,URI:repositoryUri}' \
            --output table 2>/dev/null || echo "No ECR repository found"
    else
        ecr_list
    fi

    echo -e "\n${BLUE}=== ECS Clusters ===${NC}"
    if [ -n "$stack_name" ]; then
        aws ecs describe-clusters \
            --clusters "$stack_name" \
            --query 'clusters[*].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,Services:activeServicesCount}' \
            --output table 2>/dev/null || echo "No ECS cluster found"
    else
        cluster_list
    fi

    echo -e "\n${BLUE}=== ECS Services ===${NC}"
    if [ -n "$stack_name" ]; then
        local services=$(aws ecs list-services --cluster "$stack_name" --query 'serviceArns' --output text 2>/dev/null)
        if [ -n "$services" ]; then
            aws ecs describe-services \
                --cluster "$stack_name" \
                --services $services \
                --query 'services[*].{Name:serviceName,Status:status,Desired:desiredCount,Running:runningCount}' \
                --output table
        else
            echo "No services found"
        fi
    else
        echo "Specify a stack name to list services"
    fi

    echo -e "\n${BLUE}=== Application Load Balancers ===${NC}"
    if [ -n "$stack_name" ]; then
        aws elbv2 describe-load-balancers \
            --names "$stack_name-alb" \
            --query 'LoadBalancers[*].{Name:LoadBalancerName,DNSName:DNSName,State:State.Code}' \
            --output table 2>/dev/null || echo "No ALB found"
    else
        alb_list
    fi

    echo -e "\n${BLUE}=== Target Groups ===${NC}"
    if [ -n "$stack_name" ]; then
        aws elbv2 describe-target-groups \
            --names "$stack_name-tg" \
            --query 'TargetGroups[*].{Name:TargetGroupName,Port:Port,TargetType:TargetType}' \
            --output table 2>/dev/null || echo "No target group found"
    else
        tg_list
    fi
}

# =============================================================================
# Main Command Handler
# =============================================================================
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
    vpc-list)
        vpc_list
        ;;
    vpc-show)
        vpc_show "$@"
        ;;
    vpc-delete)
        vpc_delete "$@"
        ;;

    # ECR
    ecr-create)
        ecr_create "$@"
        ;;
    ecr-list)
        ecr_list
        ;;
    ecr-delete)
        ecr_delete "$@"
        ;;
    ecr-login)
        ecr_login
        ;;
    ecr-push)
        ecr_push "$@"
        ;;
    ecr-images)
        ecr_images "$@"
        ;;

    # ECS Cluster
    cluster-create)
        cluster_create "$@"
        ;;
    cluster-list)
        cluster_list
        ;;
    cluster-delete)
        cluster_delete "$@"
        ;;

    # Task Definition
    task-create)
        task_create "$@"
        ;;
    task-list)
        task_list
        ;;
    task-show)
        task_show "$@"
        ;;
    task-delete)
        task_delete "$@"
        ;;

    # ECS Service
    service-create)
        service_create "$@"
        ;;
    service-list)
        service_list "$@"
        ;;
    service-show)
        service_show "$@"
        ;;
    service-update)
        service_update "$@"
        ;;
    service-delete)
        service_delete "$@"
        ;;

    # ALB
    alb-create)
        alb_create "$@"
        ;;
    alb-list)
        alb_list
        ;;
    alb-delete)
        alb_delete "$@"
        ;;
    tg-create)
        tg_create "$@"
        ;;
    tg-list)
        tg_list
        ;;
    tg-delete)
        tg_delete "$@"
        ;;
    listener-create)
        listener_create "$@"
        ;;
    listener-delete)
        listener_delete "$@"
        ;;

    # Security Groups
    sg-create-alb)
        sg_create_alb "$@"
        ;;
    sg-create-ecs)
        sg_create_ecs "$@"
        ;;
    sg-list)
        sg_list "$@"
        ;;
    sg-delete)
        sg_delete "$@"
        ;;

    # IAM
    iam-create-task-role)
        iam_create_task_role "$@"
        ;;
    iam-delete-task-role)
        iam_delete_task_role "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
