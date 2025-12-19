#!/bin/bash
# =============================================================================
# ECS on EC2 with Session Manager Architecture Script
# =============================================================================
# This script creates and manages the following architecture:
#   - VPC with public and private subnets (2 AZs)
#   - Internet Gateway and NAT Gateway
#   - EC2 instances in private subnet with ECS-optimized AMI
#   - ECS cluster with EC2 capacity provider
#   - Session Manager access for EC2 instances
#   - Optional: ECR repository for container images
#
# Key Features:
#   - EC2 instances in private subnet (no public IP)
#   - NAT Gateway for outbound internet access
#   - Session Manager for secure shell access (no SSH bastion needed)
#   - ECS container runtime for container workloads
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
DEFAULT_INSTANCE_TYPE="t3.micro"
DEFAULT_DESIRED_CAPACITY=1
DEFAULT_MIN_SIZE=1
DEFAULT_MAX_SIZE=2
DEFAULT_CONTAINER_PORT=80

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "ECS on EC2 with Session Manager Architecture"
    echo ""
    echo "  Private Subnet (EC2 with ECS) -> NAT Gateway -> Internet"
    echo "  Session Manager -> EC2 Instance -> Container"
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
    echo "  === ECR (Optional) ==="
    echo "  ecr-create <repo-name>                 - Create ECR repository"
    echo "  ecr-list                               - List ECR repositories"
    echo "  ecr-delete <repo-name>                 - Delete ECR repository"
    echo "  ecr-login                              - Login to ECR (docker)"
    echo "  ecr-push <repo-name> <image:tag>       - Tag and push image to ECR"
    echo ""
    echo "  === ECS Cluster ==="
    echo "  cluster-create <name>                  - Create ECS cluster (EC2 mode)"
    echo "  cluster-list                           - List ECS clusters"
    echo "  cluster-delete <name>                  - Delete ECS cluster"
    echo ""
    echo "  === EC2 Instances ==="
    echo "  ec2-launch <name> <subnet-id> <sg-id> <cluster-name> [instance-type]"
    echo "                                         - Launch ECS EC2 instance"
    echo "  ec2-list [cluster-name]                - List EC2 instances"
    echo "  ec2-terminate <instance-id>            - Terminate EC2 instance"
    echo "  ec2-get-ami                            - Get latest ECS-optimized AMI ID"
    echo ""
    echo "  === Auto Scaling Group ==="
    echo "  asg-create <name> <subnets> <cluster-name> [instance-type] [desired]"
    echo "                                         - Create Auto Scaling Group with Launch Template"
    echo "  asg-list                               - List Auto Scaling Groups"
    echo "  asg-update <name> <desired> [min] [max]- Update ASG capacity"
    echo "  asg-delete <name>                      - Delete Auto Scaling Group and Launch Template"
    echo ""
    echo "  === Task Definition ==="
    echo "  task-create <family> <image> [port] [cpu] [memory]"
    echo "                                         - Create EC2 task definition"
    echo "  task-list                              - List task definitions"
    echo "  task-show <family>                     - Show task definition details"
    echo "  task-delete <family>                   - Deregister all revisions"
    echo ""
    echo "  === ECS Service ==="
    echo "  service-create <cluster> <name> <task-def> [desired-count]"
    echo "                                         - Create ECS service"
    echo "  service-list <cluster>                 - List services in cluster"
    echo "  service-update <cluster> <name> <task-def> [count]"
    echo "                                         - Update service"
    echo "  service-delete <cluster> <name>        - Delete service"
    echo ""
    echo "  === Session Manager ==="
    echo "  ssm-connect <instance-id>              - Connect to EC2 via Session Manager"
    echo "  ssm-list                               - List instances available for Session Manager"
    echo "  ssm-run <instance-id> <command>        - Run command on instance via SSM"
    echo ""
    echo "  === Security Groups ==="
    echo "  sg-create-ecs <name> <vpc-id>          - Create ECS EC2 security group"
    echo "  sg-list <vpc-id>                       - List security groups in VPC"
    echo "  sg-delete <sg-id>                      - Delete security group"
    echo ""
    echo "  === IAM ==="
    echo "  iam-create-ec2-role <name>             - Create EC2 instance role (ECS + SSM)"
    echo "  iam-create-task-role <name>            - Create ECS task execution role"
    echo "  iam-delete-role <name>                 - Delete IAM role"
    echo ""
    echo "Examples:"
    echo "  # Deploy full stack with nginx container"
    echo "  $0 deploy my-ecs-app"
    echo ""
    echo "  # Connect to EC2 instance via Session Manager"
    echo "  $0 ssm-connect i-1234567890abcdef0"
    echo ""
    echo "  # Check running containers on EC2"
    echo "  $0 ssm-run i-1234567890abcdef0 'docker ps'"
    echo ""
    echo "  # Check container logs"
    echo "  $0 ssm-run i-1234567890abcdef0 'docker logs \$(docker ps -q)'"
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

    # Create public subnets (for NAT Gateway)
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

    # Create private subnets (for EC2 instances)
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

    # Enable auto-assign public IP for public subnets
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
    echo "EC2 instances will be launched in private subnets with NAT Gateway access"
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

    echo -e "\n${BLUE}=== EC2 Instances ===${NC}"
    aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,Type:InstanceType,State:State.Name,PrivateIP:PrivateIpAddress,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output table
}

vpc_delete() {
    local vpc_id=$1
    require_param "$vpc_id" "VPC ID"

    confirm_action "This will delete VPC $vpc_id and ALL associated resources (NAT Gateway, subnets, EC2 instances, etc.)"

    log_step "Deleting VPC: $vpc_id"

    # Terminate EC2 instances
    log_info "Terminating EC2 instances..."
    local instances=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text)
    if [ -n "$instances" ]; then
        aws ec2 terminate-instances --instance-ids $instances > /dev/null
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids $instances 2>/dev/null || true
    fi

    # Delete Auto Scaling Groups
    log_info "Deleting Auto Scaling Groups..."
    local asgs=$(aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[?VPCZoneIdentifier!=null].AutoScalingGroupName" --output text)
    for asg in $asgs; do
        local asg_vpc=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$asg" \
            --query 'AutoScalingGroups[0].VPCZoneIdentifier' --output text)
        # Check if ASG is in this VPC
        local subnet_check=$(aws ec2 describe-subnets \
            --subnet-ids ${asg_vpc//,/ } \
            --query "Subnets[?VpcId=='$vpc_id'].SubnetId" --output text 2>/dev/null || true)
        if [ -n "$subnet_check" ]; then
            aws autoscaling update-auto-scaling-group \
                --auto-scaling-group-name "$asg" \
                --min-size 0 --max-size 0 --desired-capacity 0 2>/dev/null || true
            sleep 5
            aws autoscaling delete-auto-scaling-group \
                --auto-scaling-group-name "$asg" --force-delete 2>/dev/null || true
            log_info "Deleted ASG: $asg"
        fi
    done

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

    # Delete Network Interfaces
    log_info "Deleting Network Interfaces..."
    local enis=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
    for eni in $enis; do
        aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
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

# =============================================================================
# ECS Cluster Functions
# =============================================================================
cluster_create() {
    local name=$1
    require_param "$name" "Cluster name"

    log_step "Creating ECS cluster (EC2 mode): $name"

    aws ecs create-cluster \
        --cluster-name "$name" \
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
        --query 'clusters[*].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,ContainerInstances:registeredContainerInstancesCount,Services:activeServicesCount}' \
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
# EC2 Functions
# =============================================================================
ec2_get_ami() {
    local region=$(get_region)

    log_step "Getting latest ECS-optimized AMI for region: $region"

    local ami_id
    ami_id=$(aws ssm get-parameters \
        --names /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id \
        --query 'Parameters[0].Value' --output text)

    log_success "Latest ECS-optimized AMI: $ami_id"
    echo "$ami_id"
}

ec2_launch() {
    local name=$1
    local subnet_id=$2
    local sg_id=$3
    local cluster_name=$4
    local instance_type=${5:-$DEFAULT_INSTANCE_TYPE}

    require_param "$name" "Instance name"
    require_param "$subnet_id" "Subnet ID"
    require_param "$sg_id" "Security group ID"
    require_param "$cluster_name" "ECS cluster name"

    log_step "Launching ECS EC2 instance: $name"

    local ami_id=$(ec2_get_ami 2>/dev/null | tail -1)
    local account_id=$(get_account_id)

    # Check/create instance profile
    local instance_profile="${cluster_name}-ec2-instance-profile"
    if ! aws iam get-instance-profile --instance-profile-name "$instance_profile" &>/dev/null; then
        log_info "Creating instance profile: $instance_profile"
        iam_create_ec2_role "${cluster_name}-ec2-role"
        aws iam create-instance-profile --instance-profile-name "$instance_profile" 2>/dev/null || true
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$instance_profile" \
            --role-name "${cluster_name}-ec2-role" 2>/dev/null || true
        sleep 10
    fi

    # User data to join ECS cluster
    local user_data=$(cat << EOF
#!/bin/bash
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
EOF
)
    local user_data_base64=$(echo "$user_data" | base64 -w 0)

    local instance_id
    instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --subnet-id "$subnet_id" \
        --security-group-ids "$sg_id" \
        --iam-instance-profile Name="$instance_profile" \
        --user-data "$user_data_base64" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name},{Key=ECSCluster,Value=$cluster_name}]" \
        --query 'Instances[0].InstanceId' --output text)

    log_info "Launched instance: $instance_id"
    log_info "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$instance_id"

    log_success "Instance is running: $instance_id"
    echo ""
    echo "Instance ID: $instance_id"
    echo ""
    echo "Connect via Session Manager:"
    echo "  $0 ssm-connect $instance_id"
    echo "  aws ssm start-session --target $instance_id"
}

ec2_list() {
    local cluster_name=$1

    log_step "Listing ECS EC2 instances..."

    local filter=""
    if [ -n "$cluster_name" ]; then
        filter="Name=tag:ECSCluster,Values=$cluster_name"
        aws ec2 describe-instances \
            --filters "$filter" "Name=instance-state-name,Values=running,pending,stopped" \
            --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,Type:InstanceType,State:State.Name,PrivateIP:PrivateIpAddress,Name:Tags[?Key==`Name`].Value|[0],Cluster:Tags[?Key==`ECSCluster`].Value|[0]}' \
            --output table
    else
        aws ec2 describe-instances \
            --filters "Name=tag-key,Values=ECSCluster" "Name=instance-state-name,Values=running,pending,stopped" \
            --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,Type:InstanceType,State:State.Name,PrivateIP:PrivateIpAddress,Name:Tags[?Key==`Name`].Value|[0],Cluster:Tags[?Key==`ECSCluster`].Value|[0]}' \
            --output table
    fi
}

ec2_terminate() {
    local instance_id=$1
    require_param "$instance_id" "Instance ID"

    confirm_action "This will terminate EC2 instance $instance_id"

    log_step "Terminating instance: $instance_id"
    aws ec2 terminate-instances --instance-ids "$instance_id"
    log_success "Instance termination initiated: $instance_id"
}

# =============================================================================
# Auto Scaling Group Functions
# =============================================================================
asg_create() {
    local name=$1
    local subnets=$2
    local cluster_name=$3
    local instance_type=${4:-$DEFAULT_INSTANCE_TYPE}
    local desired=${5:-$DEFAULT_DESIRED_CAPACITY}

    require_param "$name" "ASG name"
    require_param "$subnets" "Subnet IDs (comma-separated)"
    require_param "$cluster_name" "ECS cluster name"

    log_step "Creating Auto Scaling Group: $name"

    local ami_id=$(ec2_get_ami 2>/dev/null | tail -1)
    local account_id=$(get_account_id)

    # Get VPC ID from first subnet
    local first_subnet=$(echo "$subnets" | cut -d',' -f1)
    local vpc_id=$(aws ec2 describe-subnets --subnet-ids "$first_subnet" \
        --query 'Subnets[0].VpcId' --output text)

    # Create security group if not exists
    local sg_name="${name}-sg"
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=$sg_name" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

    if [ -z "$sg_id" ] || [ "$sg_id" == "None" ]; then
        sg_id=$(sg_create_ecs "$sg_name" "$vpc_id" 2>/dev/null | grep "Security Group ID:" | awk '{print $4}')
    fi

    # Check/create instance profile
    local role_name="${cluster_name}-ec2-role"
    local instance_profile="${cluster_name}-ec2-instance-profile"
    if ! aws iam get-instance-profile --instance-profile-name "$instance_profile" &>/dev/null; then
        log_info "Creating IAM role and instance profile..."
        iam_create_ec2_role "$role_name"
        aws iam create-instance-profile --instance-profile-name "$instance_profile" 2>/dev/null || true
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$instance_profile" \
            --role-name "$role_name" 2>/dev/null || true
        log_info "Waiting for IAM propagation..."
        sleep 15
    fi

    # User data
    local user_data=$(cat << EOF
#!/bin/bash
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
EOF
)
    local user_data_base64=$(echo "$user_data" | base64 -w 0)

    # Create Launch Template
    local lt_name="${name}-lt"
    log_info "Creating Launch Template: $lt_name"

    aws ec2 create-launch-template \
        --launch-template-name "$lt_name" \
        --version-description "ECS EC2 Launch Template" \
        --launch-template-data "{
            \"ImageId\": \"$ami_id\",
            \"InstanceType\": \"$instance_type\",
            \"IamInstanceProfile\": {\"Name\": \"$instance_profile\"},
            \"NetworkInterfaces\": [{
                \"DeviceIndex\": 0,
                \"AssociatePublicIpAddress\": false,
                \"Groups\": [\"$sg_id\"]
            }],
            \"UserData\": \"$user_data_base64\",
            \"TagSpecifications\": [{
                \"ResourceType\": \"instance\",
                \"Tags\": [
                    {\"Key\": \"Name\", \"Value\": \"$name-instance\"},
                    {\"Key\": \"ECSCluster\", \"Value\": \"$cluster_name\"}
                ]
            }]
        }" > /dev/null

    log_info "Created Launch Template: $lt_name"

    # Create Auto Scaling Group
    log_info "Creating Auto Scaling Group: $name"

    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "$name" \
        --launch-template "LaunchTemplateName=$lt_name,Version=\$Latest" \
        --min-size "$DEFAULT_MIN_SIZE" \
        --max-size "$DEFAULT_MAX_SIZE" \
        --desired-capacity "$desired" \
        --vpc-zone-identifier "$subnets" \
        --tags "Key=Name,Value=$name-instance,PropagateAtLaunch=true" \
               "Key=ECSCluster,Value=$cluster_name,PropagateAtLaunch=true"

    log_success "Created Auto Scaling Group: $name"
    echo ""
    echo "ASG Name:           $name"
    echo "Launch Template:    $lt_name"
    echo "Instance Type:      $instance_type"
    echo "Desired Capacity:   $desired"
    echo "Security Group:     $sg_id"
    echo ""
    echo "Instances will register with ECS cluster: $cluster_name"
}

asg_list() {
    log_step "Listing Auto Scaling Groups..."
    aws autoscaling describe-auto-scaling-groups \
        --query 'AutoScalingGroups[*].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:length(Instances)}' \
        --output table
}

asg_update() {
    local name=$1
    local desired=$2
    local min=${3:-$DEFAULT_MIN_SIZE}
    local max=${4:-$DEFAULT_MAX_SIZE}

    require_param "$name" "ASG name"
    require_param "$desired" "Desired capacity"

    log_step "Updating ASG: $name"

    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$name" \
        --min-size "$min" \
        --max-size "$max" \
        --desired-capacity "$desired"

    log_success "Updated ASG: $name (desired: $desired, min: $min, max: $max)"
}

asg_delete() {
    local name=$1
    require_param "$name" "ASG name"

    confirm_action "This will delete ASG '$name' and terminate all instances"

    log_step "Deleting Auto Scaling Group: $name"

    # Scale down first
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$name" \
        --min-size 0 --max-size 0 --desired-capacity 0 2>/dev/null || true

    sleep 5

    # Delete ASG
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name "$name" \
        --force-delete

    log_info "Deleted ASG: $name"

    # Delete Launch Template
    local lt_name="${name}-lt"
    aws ec2 delete-launch-template --launch-template-name "$lt_name" 2>/dev/null || true
    log_info "Deleted Launch Template: $lt_name"

    log_success "Deleted Auto Scaling Group and Launch Template"
}

# =============================================================================
# Task Definition Functions
# =============================================================================
task_create() {
    local family=$1
    local image=$2
    local port=${3:-$DEFAULT_CONTAINER_PORT}
    local cpu=${4:-256}
    local memory=${5:-512}

    require_param "$family" "Task family name"
    require_param "$image" "Container image"

    log_step "Creating EC2 task definition: $family"

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
    "networkMode": "bridge",
    "requiresCompatibilities": ["EC2"],
    "executionRoleArn": "$execution_role_arn",
    "containerDefinitions": [
        {
            "name": "$family",
            "image": "$image",
            "essential": true,
            "cpu": $cpu,
            "memory": $memory,
            "portMappings": [
                {
                    "containerPort": $port,
                    "hostPort": 0,
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
        --query 'taskDefinition.{Family:family,Revision:revision,Status:status}' \
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
        --query 'taskDefinition.{Family:family,Revision:revision,Status:status,NetworkMode:networkMode,Image:containerDefinitions[0].image,Port:containerDefinitions[0].portMappings[0].containerPort}' \
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
    local desired=${4:-1}

    require_param "$cluster" "Cluster name"
    require_param "$name" "Service name"
    require_param "$task_def" "Task definition"

    log_step "Creating ECS service: $name"

    aws ecs create-service \
        --cluster "$cluster" \
        --service-name "$name" \
        --task-definition "$task_def" \
        --desired-count "$desired" \
        --launch-type EC2 \
        --scheduling-strategy REPLICA \
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

service_update() {
    local cluster=$1
    local name=$2
    local task_def=$3
    local count=${4:-1}

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
# Session Manager Functions
# =============================================================================
ssm_connect() {
    local instance_id=$1
    require_param "$instance_id" "Instance ID"

    log_step "Connecting to instance via Session Manager: $instance_id"
    echo ""
    echo "Starting Session Manager session..."
    echo "Type 'exit' to end the session"
    echo ""

    aws ssm start-session --target "$instance_id"
}

ssm_list() {
    log_step "Listing instances available for Session Manager..."

    aws ssm describe-instance-information \
        --query 'InstanceInformationList[*].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformType:PlatformType,PlatformName:PlatformName}' \
        --output table
}

ssm_run() {
    local instance_id=$1
    local command=$2

    require_param "$instance_id" "Instance ID"
    require_param "$command" "Command"

    log_step "Running command on instance: $instance_id"
    log_info "Command: $command"
    echo ""

    local command_id
    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"$command\"]" \
        --query 'Command.CommandId' --output text)

    # Wait for command to complete
    sleep 2

    aws ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$instance_id" \
        --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
        --output yaml
}

# =============================================================================
# Security Group Functions
# =============================================================================
sg_create_ecs() {
    local name=$1
    local vpc_id=$2

    require_param "$name" "Security group name"
    require_param "$vpc_id" "VPC ID"

    log_step "Creating ECS EC2 security group: $name"

    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "ECS EC2 security group - allows outbound traffic" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' --output text)

    # Allow all outbound traffic (already default, but explicit)
    # No inbound rules needed - traffic goes through NAT Gateway

    # Allow inbound from VPC CIDR for inter-container communication
    local vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].CidrBlock' --output text)

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol -1 \
        --cidr "$vpc_cidr" > /dev/null

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
iam_create_ec2_role() {
    local role_name=$1
    require_param "$role_name" "Role name"

    log_step "Creating EC2 instance role (ECS + SSM): $role_name"

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    # ECS permissions
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role 2>/dev/null || true

    # SSM permissions for Session Manager
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

    # CloudWatch Logs permissions
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess 2>/dev/null || true

    # ECR read permissions
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true

    log_success "Created EC2 instance role: $role_name"
    echo ""
    echo "Attached policies:"
    echo "  - AmazonEC2ContainerServiceforEC2Role (ECS agent)"
    echo "  - AmazonSSMManagedInstanceCore (Session Manager)"
    echo "  - CloudWatchLogsFullAccess (Container logs)"
    echo "  - AmazonEC2ContainerRegistryReadOnly (ECR pull)"
}

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

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess 2>/dev/null || true

    log_success "Created ECS task execution role: $role_name"
}

iam_delete_role() {
    local role_name=$1
    require_param "$role_name" "Role name"

    confirm_action "This will delete IAM role '$role_name'"

    log_step "Deleting IAM role: $role_name"

    # Remove from instance profiles
    local profiles=$(aws iam list-instance-profiles-for-role --role-name "$role_name" \
        --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null)
    for profile in $profiles; do
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$profile" \
            --role-name "$role_name" 2>/dev/null || true
        aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
    done

    delete_role_with_policies "$role_name"
    log_success "Deleted role: $role_name"
}

# =============================================================================
# Full Stack Orchestration
# =============================================================================
deploy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_info "Deploying ECS on EC2 with Session Manager: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets (2 AZs)"
    echo "  - Internet Gateway and NAT Gateway"
    echo "  - EC2 instances with ECS-optimized AMI in private subnet"
    echo "  - Auto Scaling Group for EC2 instances"
    echo "  - ECS cluster (EC2 mode)"
    echo "  - IAM roles (EC2 instance role with SSM, ECS task execution role)"
    echo "  - Security group for EC2 instances"
    echo "  - Sample nginx task and service"
    echo ""
    echo -e "${YELLOW}Note: EC2 instances will be in private subnet with NAT Gateway access${NC}"
    echo -e "${YELLOW}You can connect via Session Manager (no SSH/bastion needed)${NC}"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    log_step "Step 1/7: Creating IAM roles..."
    iam_create_ec2_role "${stack_name}-ec2-role"
    iam_create_task_role "ecsTaskExecutionRole"

    # Create instance profile
    local instance_profile="${stack_name}-ec2-instance-profile"
    aws iam create-instance-profile --instance-profile-name "$instance_profile" 2>/dev/null || true
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$instance_profile" \
        --role-name "${stack_name}-ec2-role" 2>/dev/null || true
    log_info "Waiting for IAM propagation..."
    sleep 15

    log_step "Step 2/7: Creating VPC..."
    vpc_create "$stack_name"
    echo ""

    # Get VPC info
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' --output text)

    local private_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=*private*" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

    log_step "Step 3/7: Creating ECS cluster..."
    cluster_create "$stack_name"
    echo ""

    log_step "Step 4/7: Creating security group..."
    local sg_id=$(sg_create_ecs "$stack_name-ecs-sg" "$vpc_id" 2>/dev/null | grep "Security Group ID:" | awk '{print $4}')
    echo ""

    log_step "Step 5/7: Creating Auto Scaling Group..."
    asg_create "${stack_name}-asg" "$private_subnets" "$stack_name"
    echo ""

    log_step "Step 6/7: Waiting for EC2 instance to register with ECS..."
    local max_wait=180
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local container_instances=$(aws ecs list-container-instances \
            --cluster "$stack_name" \
            --query 'containerInstanceArns' --output text)
        if [ -n "$container_instances" ]; then
            log_info "Container instance registered with ECS cluster"
            break
        fi
        sleep 10
        waited=$((waited + 10))
        log_info "Waiting for container instance... ($waited/$max_wait seconds)"
    done

    if [ $waited -ge $max_wait ]; then
        log_warn "Timeout waiting for container instance. Instance may still be starting."
    fi

    log_step "Step 7/7: Creating task definition and service..."
    task_create "$stack_name" "nginx:latest" 80
    sleep 5
    service_create "$stack_name" "${stack_name}-service" "$stack_name" 1
    echo ""

    # Get instance ID
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=tag:ECSCluster,Values=$stack_name" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text)

    log_success "Deployment complete!"
    echo ""
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo "Stack Name:       $stack_name"
    echo "VPC ID:           $vpc_id"
    echo "ECS Cluster:      $stack_name"
    echo "EC2 Instance:     $instance_id"
    echo "Task Definition:  $stack_name"
    echo "Service:          ${stack_name}-service"
    echo ""
    echo -e "${YELLOW}=== Connect to EC2 via Session Manager ===${NC}"
    echo "  $0 ssm-connect $instance_id"
    echo ""
    echo -e "${YELLOW}=== Check Containers on EC2 ===${NC}"
    echo "  $0 ssm-run $instance_id 'docker ps'"
    echo "  $0 ssm-run $instance_id 'docker logs \$(docker ps -q)'"
    echo ""
    echo -e "${YELLOW}=== Interactive Session ===${NC}"
    echo "  aws ssm start-session --target $instance_id"
    echo "  # Then on EC2:"
    echo "  docker ps"
    echo "  docker exec -it <container-id> /bin/sh"
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
    echo "  - Auto Scaling Group"
    echo "  - Launch Template"
    echo "  - EC2 instances"
    echo "  - Security groups"
    echo "  - IAM roles and instance profiles"
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

    # Delete Auto Scaling Group
    log_step "Deleting Auto Scaling Group..."
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "${stack_name}-asg" \
        --min-size 0 --max-size 0 --desired-capacity 0 2>/dev/null || true
    sleep 10
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name "${stack_name}-asg" \
        --force-delete 2>/dev/null || true
    log_info "Deleted ASG: ${stack_name}-asg"

    # Delete Launch Template
    log_step "Deleting Launch Template..."
    aws ec2 delete-launch-template --launch-template-name "${stack_name}-asg-lt" 2>/dev/null || true
    log_info "Deleted Launch Template"

    # Wait for instances to terminate
    log_step "Waiting for EC2 instances to terminate..."
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:ECSCluster,Values=$stack_name" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null)
    if [ -n "$instances" ]; then
        aws ec2 wait instance-terminated --instance-ids $instances 2>/dev/null || true
    fi

    # Deregister container instances
    log_step "Deregistering container instances..."
    local container_instances=$(aws ecs list-container-instances \
        --cluster "$stack_name" \
        --query 'containerInstanceArns' --output text 2>/dev/null)
    for ci in $container_instances; do
        aws ecs deregister-container-instance \
            --cluster "$stack_name" \
            --container-instance "$ci" \
            --force 2>/dev/null || true
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

    # Delete security groups
    log_step "Deleting security groups..."
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        sleep 5
        local sgs=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=$stack_name*" \
            --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null)
        for sg in $sgs; do
            aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
            log_info "Deleted security group: $sg"
        done
    fi

    # Delete IAM roles and instance profiles
    log_step "Deleting IAM roles..."
    local instance_profile="${stack_name}-ec2-instance-profile"
    local role_name="${stack_name}-ec2-role"

    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$instance_profile" \
        --role-name "$role_name" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$instance_profile" 2>/dev/null || true
    delete_role_with_policies "$role_name" 2>/dev/null || true
    log_info "Deleted IAM role and instance profile"

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

    echo -e "\n${BLUE}=== ECS Clusters ===${NC}"
    if [ -n "$stack_name" ]; then
        aws ecs describe-clusters \
            --clusters "$stack_name" \
            --query 'clusters[*].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,ContainerInstances:registeredContainerInstancesCount}' \
            --output table 2>/dev/null || echo "No ECS cluster found"
    else
        cluster_list
    fi

    echo -e "\n${BLUE}=== EC2 Instances ===${NC}"
    if [ -n "$stack_name" ]; then
        ec2_list "$stack_name"
    else
        ec2_list
    fi

    echo -e "\n${BLUE}=== Auto Scaling Groups ===${NC}"
    if [ -n "$stack_name" ]; then
        aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "${stack_name}-asg" \
            --query 'AutoScalingGroups[*].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:length(Instances)}' \
            --output table 2>/dev/null || echo "No ASG found"
    else
        asg_list
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

    echo -e "\n${BLUE}=== Session Manager Availability ===${NC}"
    ssm_list
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

    # EC2
    ec2-launch)
        ec2_launch "$@"
        ;;
    ec2-list)
        ec2_list "$@"
        ;;
    ec2-terminate)
        ec2_terminate "$@"
        ;;
    ec2-get-ami)
        ec2_get_ami
        ;;

    # ASG
    asg-create)
        asg_create "$@"
        ;;
    asg-list)
        asg_list
        ;;
    asg-update)
        asg_update "$@"
        ;;
    asg-delete)
        asg_delete "$@"
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
    service-update)
        service_update "$@"
        ;;
    service-delete)
        service_delete "$@"
        ;;

    # Session Manager
    ssm-connect)
        ssm_connect "$@"
        ;;
    ssm-list)
        ssm_list
        ;;
    ssm-run)
        ssm_run "$@"
        ;;

    # Security Groups
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
    iam-create-ec2-role)
        iam_create_ec2_role "$@"
        ;;
    iam-create-task-role)
        iam_create_task_role "$@"
        ;;
    iam-delete-role)
        iam_delete_role "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
