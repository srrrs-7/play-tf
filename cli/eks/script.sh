#!/bin/bash
# =============================================================================
# Amazon EKS CLI Script
# =============================================================================
# This script creates and manages EKS (Elastic Kubernetes Service) clusters:
#   - VPC with public/private subnets
#   - EKS cluster (control plane)
#   - Managed Node Groups (EC2)
#   - Fargate profiles (optional)
#   - Add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI)
#   - IAM roles and policies
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
DEFAULT_K8S_VERSION="1.29"
DEFAULT_INSTANCE_TYPE="t3.medium"
DEFAULT_NODE_COUNT=2
DEFAULT_VPC_CIDR="10.0.0.0/16"

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Amazon EKS (Elastic Kubernetes Service) CLI"
    echo ""
    echo "Commands:"
    echo ""
    echo "  === Full Stack ==="
    echo "  deploy <cluster-name> [version]        - Deploy full EKS stack"
    echo "  destroy <cluster-name>                 - Destroy all resources"
    echo "  status [cluster-name]                  - Show status"
    echo ""
    echo "  === VPC ==="
    echo "  vpc-create <name> [cidr]               - Create VPC with subnets"
    echo "  vpc-list                               - List VPCs"
    echo "  vpc-delete <vpc-id>                    - Delete VPC"
    echo ""
    echo "  === IAM Roles ==="
    echo "  iam-create-cluster-role <name>         - Create cluster IAM role"
    echo "  iam-create-node-role <name>            - Create node IAM role"
    echo "  iam-delete-role <name>                 - Delete IAM role"
    echo ""
    echo "  === EKS Cluster ==="
    echo "  cluster-create <name> <subnets> [version]"
    echo "                                         - Create EKS cluster"
    echo "  cluster-list                           - List clusters"
    echo "  cluster-show <name>                    - Show cluster details"
    echo "  cluster-delete <name>                  - Delete cluster"
    echo "  cluster-update-version <name> <version>- Update cluster version"
    echo ""
    echo "  === Node Groups ==="
    echo "  nodegroup-create <cluster> <name> <subnets> [instance-type] [count]"
    echo "                                         - Create managed node group"
    echo "  nodegroup-list <cluster>               - List node groups"
    echo "  nodegroup-show <cluster> <name>        - Show node group details"
    echo "  nodegroup-scale <cluster> <name> <count>"
    echo "                                         - Scale node group"
    echo "  nodegroup-delete <cluster> <name>      - Delete node group"
    echo ""
    echo "  === Fargate ==="
    echo "  fargate-create <cluster> <name> <subnets> <namespace>"
    echo "                                         - Create Fargate profile"
    echo "  fargate-list <cluster>                 - List Fargate profiles"
    echo "  fargate-delete <cluster> <name>        - Delete Fargate profile"
    echo ""
    echo "  === Add-ons ==="
    echo "  addon-list <cluster>                   - List installed add-ons"
    echo "  addon-install <cluster> <addon-name>   - Install add-on"
    echo "  addon-delete <cluster> <addon-name>    - Delete add-on"
    echo "  addon-available                        - List available add-ons"
    echo ""
    echo "  === kubectl Configuration ==="
    echo "  kubeconfig <cluster>                   - Update kubeconfig"
    echo "  kubectl-test <cluster>                 - Test kubectl connectivity"
    echo ""
    echo "  === Sample Applications ==="
    echo "  sample-deploy <cluster>                - Deploy sample nginx app"
    echo "  sample-delete <cluster>                - Delete sample app"
    echo ""
    echo "Examples:"
    echo "  # Deploy full EKS stack with managed nodes"
    echo "  $0 deploy my-cluster"
    echo ""
    echo "  # Deploy with specific version"
    echo "  $0 deploy my-cluster 1.29"
    echo ""
    echo "  # Scale node group"
    echo "  $0 nodegroup-scale my-cluster my-cluster-nodes 3"
    echo ""
    echo "  # Deploy sample application"
    echo "  $0 sample-deploy my-cluster"
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

    log_step "Creating VPC for EKS: $name"

    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name},{Key=kubernetes.io/cluster/$name,Value=shared}]" \
        --query 'Vpc.VpcId' --output text)
    log_info "Created VPC: $vpc_id"

    # Enable DNS
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support

    # Get AZs
    local azs
    azs=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[?State==`available`].ZoneName' --output text | head -2 | tr '\t' ' ')
    local az_array=($azs)

    if [ ${#az_array[@]} -lt 2 ]; then
        log_error "Need at least 2 availability zones"
        exit 1
    fi

    # Create Internet Gateway
    log_info "Creating Internet Gateway..."
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$name-igw}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 attach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"

    # Create public subnets
    log_info "Creating public subnets..."
    local public_subnet_1
    public_subnet_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.1.0/24" \
        --availability-zone "${az_array[0]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-1},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/$name,Value=shared}]" \
        --query 'Subnet.SubnetId' --output text)

    local public_subnet_2
    public_subnet_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.2.0/24" \
        --availability-zone "${az_array[1]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-2},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/$name,Value=shared}]" \
        --query 'Subnet.SubnetId' --output text)

    # Create private subnets
    log_info "Creating private subnets..."
    local private_subnet_1
    private_subnet_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.11.0/24" \
        --availability-zone "${az_array[0]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-1},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/$name,Value=shared}]" \
        --query 'Subnet.SubnetId' --output text)

    local private_subnet_2
    private_subnet_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.12.0/24" \
        --availability-zone "${az_array[1]}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-2},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/$name,Value=shared}]" \
        --query 'Subnet.SubnetId' --output text)

    # Public route table
    log_info "Creating route tables..."
    local public_rt
    public_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-public-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route --route-table-id "$public_rt" --destination-cidr-block "0.0.0.0/0" --gateway-id "$igw_id" > /dev/null
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_1" > /dev/null
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_2" > /dev/null

    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_1" --map-public-ip-on-launch
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_2" --map-public-ip-on-launch

    # NAT Gateway
    log_info "Creating NAT Gateway (this takes a few minutes)..."
    local eip_alloc
    eip_alloc=$(aws ec2 allocate-address --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$name-nat-eip}]" \
        --query 'AllocationId' --output text)

    local nat_gw
    nat_gw=$(aws ec2 create-nat-gateway \
        --subnet-id "$public_subnet_1" \
        --allocation-id "$eip_alloc" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$name-nat}]" \
        --query 'NatGateway.NatGatewayId' --output text)

    aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat_gw"
    log_info "NAT Gateway ready: $nat_gw"

    # Private route table
    local private_rt
    private_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-private-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route --route-table-id "$private_rt" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "$nat_gw" > /dev/null
    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet_1" > /dev/null
    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet_2" > /dev/null

    log_success "VPC created successfully!"
    echo ""
    echo -e "${GREEN}=== VPC Summary ===${NC}"
    echo "VPC ID:           $vpc_id"
    echo "Public Subnets:   $public_subnet_1, $public_subnet_2"
    echo "Private Subnets:  $private_subnet_1, $private_subnet_2"
    echo ""
    echo "For EKS cluster, use private subnets:"
    echo "  $private_subnet_1,$private_subnet_2"
}

vpc_list() {
    log_step "Listing VPCs..."
    aws ec2 describe-vpcs \
        --query 'Vpcs[*].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output table
}

vpc_delete() {
    local vpc_id=$1
    require_param "$vpc_id" "VPC ID"

    confirm_action "This will delete VPC $vpc_id and ALL associated resources"

    log_step "Deleting VPC resources..."

    # Delete NAT Gateways
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
        sleep 60
    fi

    # Release Elastic IPs
    local eips=$(aws ec2 describe-addresses \
        --filters "Name=domain,Values=vpc" \
        --query "Addresses[?NetworkInterfaceId==null].AllocationId" --output text)
    for eip in $eips; do
        aws ec2 release-address --allocation-id "$eip" 2>/dev/null || true
    done

    # Delete subnets
    local subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].SubnetId' --output text)
    for subnet in $subnets; do
        aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
    done

    # Delete route tables
    local route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for rt in $route_tables; do
        local associations=$(aws ec2 describe-route-tables \
            --route-table-ids "$rt" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text)
        for assoc in $associations; do
            aws ec2 disassociate-route-table --association-id "$assoc" 2>/dev/null || true
        done
        aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
    done

    # Detach and delete Internet Gateway
    local igws=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[*].InternetGatewayId' --output text)
    for igw in $igws; do
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    done

    # Delete security groups
    local sgs=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for sg in $sgs; do
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_success "Deleted VPC: $vpc_id"
}

# =============================================================================
# IAM Role Functions
# =============================================================================
iam_create_cluster_role() {
    local name=$1
    require_param "$name" "Role name"

    log_step "Creating EKS cluster IAM role: $name"

    local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "eks.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
)

    aws iam create-role \
        --role-name "$name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || log_info "Role already exists"

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController 2>/dev/null || true

    log_success "Created cluster role: $name"
}

iam_create_node_role() {
    local name=$1
    require_param "$name" "Role name"

    log_step "Creating EKS node IAM role: $name"

    local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
)

    aws iam create-role \
        --role-name "$name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || log_info "Role already exists"

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

    log_success "Created node role: $name"
}

iam_delete_role() {
    local name=$1
    require_param "$name" "Role name"

    confirm_action "This will delete IAM role: $name"

    log_step "Deleting IAM role: $name"
    delete_role_with_policies "$name"
    log_success "Deleted role: $name"
}

# =============================================================================
# EKS Cluster Functions
# =============================================================================
cluster_create() {
    local name=$1
    local subnet_ids=$2
    local version=${3:-$DEFAULT_K8S_VERSION}

    require_param "$name" "Cluster name"
    require_param "$subnet_ids" "Subnet IDs (comma-separated)"

    log_step "Creating EKS cluster: $name (version $version)"

    local account_id=$(get_account_id)
    local cluster_role="${name}-cluster-role"

    # Create cluster role if not exists
    if ! aws iam get-role --role-name "$cluster_role" &>/dev/null; then
        iam_create_cluster_role "$cluster_role"
        sleep 10
    fi

    local role_arn="arn:aws:iam::$account_id:role/$cluster_role"

    # Convert comma-separated subnets
    local subnets_array=$(echo "$subnet_ids" | tr ',' ' ')

    aws eks create-cluster \
        --name "$name" \
        --version "$version" \
        --role-arn "$role_arn" \
        --resources-vpc-config "subnetIds=$subnets_array,endpointPublicAccess=true,endpointPrivateAccess=true"

    log_info "Cluster creation initiated. Waiting for cluster to be active..."
    log_info "This typically takes 10-15 minutes..."

    aws eks wait cluster-active --name "$name"

    log_success "Cluster $name is now active!"

    # Update kubeconfig
    log_info "Updating kubeconfig..."
    aws eks update-kubeconfig --name "$name" --region $(get_region)

    echo ""
    echo -e "${GREEN}=== Cluster Summary ===${NC}"
    aws eks describe-cluster --name "$name" \
        --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
        --output table
}

cluster_list() {
    log_step "Listing EKS clusters..."
    local clusters=$(aws eks list-clusters --query 'clusters' --output text)

    if [ -z "$clusters" ]; then
        echo "No clusters found"
        return
    fi

    for cluster in $clusters; do
        aws eks describe-cluster --name "$cluster" \
            --query 'cluster.{Name:name,Status:status,Version:version,CreatedAt:createdAt}' \
            --output table
    done
}

cluster_show() {
    local name=$1
    require_param "$name" "Cluster name"

    log_step "Showing cluster: $name"
    aws eks describe-cluster --name "$name" --output yaml
}

cluster_delete() {
    local name=$1
    require_param "$name" "Cluster name"

    confirm_action "This will delete EKS cluster: $name"

    log_step "Deleting EKS cluster: $name"

    # Delete node groups first
    log_info "Deleting node groups..."
    local node_groups=$(aws eks list-nodegroups --cluster-name "$name" --query 'nodegroups' --output text 2>/dev/null)
    for ng in $node_groups; do
        aws eks delete-nodegroup --cluster-name "$name" --nodegroup-name "$ng"
        log_info "Deleting node group: $ng"
    done

    # Wait for node groups to be deleted
    for ng in $node_groups; do
        aws eks wait nodegroup-deleted --cluster-name "$name" --nodegroup-name "$ng" 2>/dev/null || true
    done

    # Delete Fargate profiles
    log_info "Deleting Fargate profiles..."
    local fargate_profiles=$(aws eks list-fargate-profiles --cluster-name "$name" --query 'fargateProfileNames' --output text 2>/dev/null)
    for fp in $fargate_profiles; do
        aws eks delete-fargate-profile --cluster-name "$name" --fargate-profile-name "$fp"
        log_info "Deleting Fargate profile: $fp"
    done

    # Wait for Fargate profiles
    for fp in $fargate_profiles; do
        aws eks wait fargate-profile-deleted --cluster-name "$name" --fargate-profile-name "$fp" 2>/dev/null || true
    done

    # Delete cluster
    log_info "Deleting cluster..."
    aws eks delete-cluster --name "$name"
    aws eks wait cluster-deleted --name "$name"

    log_success "Deleted cluster: $name"
}

cluster_update_version() {
    local name=$1
    local version=$2

    require_param "$name" "Cluster name"
    require_param "$version" "Kubernetes version"

    log_step "Updating cluster $name to version $version"

    aws eks update-cluster-version --name "$name" --kubernetes-version "$version"

    log_info "Update initiated. This may take 20-30 minutes..."
    log_info "Check status with: $0 cluster-show $name"
}

# =============================================================================
# Node Group Functions
# =============================================================================
nodegroup_create() {
    local cluster=$1
    local name=$2
    local subnet_ids=$3
    local instance_type=${4:-$DEFAULT_INSTANCE_TYPE}
    local count=${5:-$DEFAULT_NODE_COUNT}

    require_param "$cluster" "Cluster name"
    require_param "$name" "Node group name"
    require_param "$subnet_ids" "Subnet IDs (comma-separated)"

    log_step "Creating node group: $name"

    local account_id=$(get_account_id)
    local node_role="${cluster}-node-role"

    # Create node role if not exists
    if ! aws iam get-role --role-name "$node_role" &>/dev/null; then
        iam_create_node_role "$node_role"
        sleep 10
    fi

    local role_arn="arn:aws:iam::$account_id:role/$node_role"
    local subnets_array=$(echo "$subnet_ids" | tr ',' ' ')

    aws eks create-nodegroup \
        --cluster-name "$cluster" \
        --nodegroup-name "$name" \
        --node-role "$role_arn" \
        --subnets $subnets_array \
        --instance-types "$instance_type" \
        --scaling-config "minSize=1,maxSize=$((count * 2)),desiredSize=$count" \
        --capacity-type ON_DEMAND \
        --ami-type AL2_x86_64

    log_info "Node group creation initiated. Waiting..."
    aws eks wait nodegroup-active --cluster-name "$cluster" --nodegroup-name "$name"

    log_success "Node group $name is now active!"
}

nodegroup_list() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Listing node groups for: $cluster"

    local node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --query 'nodegroups' --output text)

    if [ -z "$node_groups" ]; then
        echo "No node groups found"
        return
    fi

    for ng in $node_groups; do
        aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$ng" \
            --query 'nodegroup.{Name:nodegroupName,Status:status,InstanceTypes:instanceTypes[0],Desired:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize}' \
            --output table
    done
}

nodegroup_show() {
    local cluster=$1
    local name=$2

    require_param "$cluster" "Cluster name"
    require_param "$name" "Node group name"

    log_step "Showing node group: $name"
    aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$name" --output yaml
}

nodegroup_scale() {
    local cluster=$1
    local name=$2
    local count=$3

    require_param "$cluster" "Cluster name"
    require_param "$name" "Node group name"
    require_param "$count" "Desired count"

    log_step "Scaling node group $name to $count nodes"

    aws eks update-nodegroup-config \
        --cluster-name "$cluster" \
        --nodegroup-name "$name" \
        --scaling-config "desiredSize=$count"

    log_success "Scaling initiated"
}

nodegroup_delete() {
    local cluster=$1
    local name=$2

    require_param "$cluster" "Cluster name"
    require_param "$name" "Node group name"

    confirm_action "This will delete node group: $name"

    log_step "Deleting node group: $name"
    aws eks delete-nodegroup --cluster-name "$cluster" --nodegroup-name "$name"

    log_info "Waiting for node group deletion..."
    aws eks wait nodegroup-deleted --cluster-name "$cluster" --nodegroup-name "$name"

    log_success "Deleted node group: $name"
}

# =============================================================================
# Fargate Functions
# =============================================================================
fargate_create() {
    local cluster=$1
    local name=$2
    local subnet_ids=$3
    local namespace=$4

    require_param "$cluster" "Cluster name"
    require_param "$name" "Profile name"
    require_param "$subnet_ids" "Subnet IDs (comma-separated)"
    require_param "$namespace" "Kubernetes namespace"

    log_step "Creating Fargate profile: $name"

    local account_id=$(get_account_id)
    local fargate_role="${cluster}-fargate-role"

    # Create Fargate role if not exists
    if ! aws iam get-role --role-name "$fargate_role" &>/dev/null; then
        log_info "Creating Fargate IAM role..."
        local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "eks-fargate-pods.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
)
        aws iam create-role --role-name "$fargate_role" --assume-role-policy-document "$trust_policy"
        aws iam attach-role-policy --role-name "$fargate_role" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy
        sleep 10
    fi

    local role_arn="arn:aws:iam::$account_id:role/$fargate_role"
    local subnets_array=$(echo "$subnet_ids" | tr ',' ' ')

    aws eks create-fargate-profile \
        --cluster-name "$cluster" \
        --fargate-profile-name "$name" \
        --pod-execution-role-arn "$role_arn" \
        --subnets $subnets_array \
        --selectors "namespace=$namespace"

    log_info "Waiting for Fargate profile..."
    aws eks wait fargate-profile-active --cluster-name "$cluster" --fargate-profile-name "$name"

    log_success "Fargate profile $name is now active!"
}

fargate_list() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Listing Fargate profiles for: $cluster"
    aws eks list-fargate-profiles --cluster-name "$cluster" \
        --query 'fargateProfileNames' --output table
}

fargate_delete() {
    local cluster=$1
    local name=$2

    require_param "$cluster" "Cluster name"
    require_param "$name" "Profile name"

    confirm_action "This will delete Fargate profile: $name"

    log_step "Deleting Fargate profile: $name"
    aws eks delete-fargate-profile --cluster-name "$cluster" --fargate-profile-name "$name"

    log_info "Waiting for deletion..."
    aws eks wait fargate-profile-deleted --cluster-name "$cluster" --fargate-profile-name "$name"

    log_success "Deleted Fargate profile: $name"
}

# =============================================================================
# Add-on Functions
# =============================================================================
addon_list() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Listing add-ons for: $cluster"
    aws eks list-addons --cluster-name "$cluster" \
        --query 'addons' --output table
}

addon_install() {
    local cluster=$1
    local addon_name=$2

    require_param "$cluster" "Cluster name"
    require_param "$addon_name" "Add-on name"

    log_step "Installing add-on: $addon_name"

    aws eks create-addon \
        --cluster-name "$cluster" \
        --addon-name "$addon_name" \
        --resolve-conflicts OVERWRITE

    log_success "Add-on $addon_name installed"
}

addon_delete() {
    local cluster=$1
    local addon_name=$2

    require_param "$cluster" "Cluster name"
    require_param "$addon_name" "Add-on name"

    log_step "Deleting add-on: $addon_name"
    aws eks delete-addon --cluster-name "$cluster" --addon-name "$addon_name"
    log_success "Add-on $addon_name deleted"
}

addon_available() {
    log_step "Listing available add-ons..."
    aws eks describe-addon-versions \
        --query 'addons[].{Name:addonName,Versions:addonVersions[0].addonVersion}' \
        --output table
}

# =============================================================================
# kubectl Functions
# =============================================================================
update_kubeconfig() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Updating kubeconfig for: $cluster"
    aws eks update-kubeconfig --name "$cluster" --region $(get_region)
    log_success "kubeconfig updated"
}

kubectl_test() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Testing kubectl connectivity..."

    # Update kubeconfig first
    aws eks update-kubeconfig --name "$cluster" --region $(get_region) 2>/dev/null

    echo ""
    echo -e "${BLUE}=== Cluster Info ===${NC}"
    kubectl cluster-info

    echo ""
    echo -e "${BLUE}=== Nodes ===${NC}"
    kubectl get nodes

    echo ""
    echo -e "${BLUE}=== Namespaces ===${NC}"
    kubectl get namespaces

    log_success "kubectl is working!"
}

# =============================================================================
# Sample Application Functions
# =============================================================================
sample_deploy() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Deploying sample nginx application..."

    # Update kubeconfig
    aws eks update-kubeconfig --name "$cluster" --region $(get_region) 2>/dev/null

    # Create namespace
    kubectl create namespace sample-app 2>/dev/null || true

    # Deploy nginx
    cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: sample-app
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
EOF

    log_info "Waiting for LoadBalancer..."
    sleep 30

    local lb_url=$(kubectl get svc nginx-service -n sample-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

    log_success "Sample application deployed!"
    echo ""
    echo -e "${GREEN}=== Deployment Status ===${NC}"
    kubectl get pods -n sample-app
    echo ""
    kubectl get svc -n sample-app
    echo ""
    if [ -n "$lb_url" ]; then
        echo "Access your application at: http://$lb_url"
    else
        echo "LoadBalancer is still provisioning. Check with:"
        echo "  kubectl get svc nginx-service -n sample-app"
    fi
}

sample_delete() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Deleting sample application..."

    aws eks update-kubeconfig --name "$cluster" --region $(get_region) 2>/dev/null

    kubectl delete namespace sample-app 2>/dev/null || true

    log_success "Sample application deleted"
}

# =============================================================================
# Full Stack Orchestration
# =============================================================================
deploy() {
    local name=$1
    local version=${2:-$DEFAULT_K8S_VERSION}

    require_param "$name" "Cluster name"

    log_info "Deploying EKS cluster: $name (Kubernetes $version)"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets (2 AZs)"
    echo "  - NAT Gateway for private subnet internet access"
    echo "  - EKS cluster (control plane)"
    echo "  - Managed node group (2x t3.medium)"
    echo "  - IAM roles for cluster and nodes"
    echo "  - Core add-ons (CoreDNS, kube-proxy, VPC CNI)"
    echo ""
    echo -e "${YELLOW}Estimated time: 20-30 minutes${NC}"
    echo -e "${YELLOW}Estimated cost: ~\$0.10/hour (cluster) + EC2 node costs${NC}"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""

    # Step 1: Create VPC
    log_step "Step 1/5: Creating VPC..."
    vpc_create "$name"
    echo ""

    # Get subnet IDs
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$name" \
        --query 'Vpcs[0].VpcId' --output text)

    local private_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=*private*" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

    # Step 2: Create IAM roles
    log_step "Step 2/5: Creating IAM roles..."
    iam_create_cluster_role "${name}-cluster-role"
    iam_create_node_role "${name}-node-role"
    sleep 10
    echo ""

    # Step 3: Create cluster
    log_step "Step 3/5: Creating EKS cluster (this takes 10-15 minutes)..."
    local account_id=$(get_account_id)

    aws eks create-cluster \
        --name "$name" \
        --version "$version" \
        --role-arn "arn:aws:iam::$account_id:role/${name}-cluster-role" \
        --resources-vpc-config "subnetIds=${private_subnets//,/ },endpointPublicAccess=true,endpointPrivateAccess=true" \
        > /dev/null

    log_info "Waiting for cluster to be active..."
    aws eks wait cluster-active --name "$name"
    log_info "Cluster is active!"
    echo ""

    # Step 4: Create node group
    log_step "Step 4/5: Creating node group (this takes 5-10 minutes)..."

    aws eks create-nodegroup \
        --cluster-name "$name" \
        --nodegroup-name "${name}-nodes" \
        --node-role "arn:aws:iam::$account_id:role/${name}-node-role" \
        --subnets ${private_subnets//,/ } \
        --instance-types "$DEFAULT_INSTANCE_TYPE" \
        --scaling-config "minSize=1,maxSize=4,desiredSize=$DEFAULT_NODE_COUNT" \
        --capacity-type ON_DEMAND \
        --ami-type AL2_x86_64 \
        > /dev/null

    log_info "Waiting for node group to be active..."
    aws eks wait nodegroup-active --cluster-name "$name" --nodegroup-name "${name}-nodes"
    log_info "Node group is active!"
    echo ""

    # Step 5: Install add-ons and configure kubectl
    log_step "Step 5/5: Installing add-ons and configuring kubectl..."

    # Install core add-ons
    aws eks create-addon --cluster-name "$name" --addon-name vpc-cni --resolve-conflicts OVERWRITE 2>/dev/null || true
    aws eks create-addon --cluster-name "$name" --addon-name coredns --resolve-conflicts OVERWRITE 2>/dev/null || true
    aws eks create-addon --cluster-name "$name" --addon-name kube-proxy --resolve-conflicts OVERWRITE 2>/dev/null || true

    # Update kubeconfig
    aws eks update-kubeconfig --name "$name" --region $(get_region)

    echo ""
    log_success "EKS deployment complete!"
    echo ""
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo "Cluster Name:    $name"
    echo "K8s Version:     $version"
    echo "VPC ID:          $vpc_id"
    echo "Node Group:      ${name}-nodes ($DEFAULT_NODE_COUNT x $DEFAULT_INSTANCE_TYPE)"
    echo ""
    echo -e "${YELLOW}=== Quick Start ===${NC}"
    echo ""
    echo "1. Verify cluster:"
    echo "   kubectl get nodes"
    echo ""
    echo "2. Deploy sample application:"
    echo "   $0 sample-deploy $name"
    echo ""
    echo "3. Scale node group:"
    echo "   $0 nodegroup-scale $name ${name}-nodes 3"
    echo ""
    echo "4. View cluster info:"
    echo "   $0 cluster-show $name"
}

destroy() {
    local name=$1
    require_param "$name" "Cluster name"

    log_warn "This will destroy ALL resources for: $name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - EKS node groups"
    echo "  - EKS Fargate profiles"
    echo "  - EKS cluster"
    echo "  - VPC (subnets, NAT Gateway, etc.)"
    echo "  - IAM roles"
    echo "  - CloudWatch log groups"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""

    # Get VPC ID before deleting cluster
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$name" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

    # Delete node groups
    log_step "Deleting node groups..."
    local node_groups=$(aws eks list-nodegroups --cluster-name "$name" --query 'nodegroups' --output text 2>/dev/null)
    for ng in $node_groups; do
        aws eks delete-nodegroup --cluster-name "$name" --nodegroup-name "$ng" 2>/dev/null || true
        log_info "Deleting node group: $ng"
    done

    # Wait for node groups
    for ng in $node_groups; do
        aws eks wait nodegroup-deleted --cluster-name "$name" --nodegroup-name "$ng" 2>/dev/null || true
    done

    # Delete Fargate profiles
    log_step "Deleting Fargate profiles..."
    local fargate_profiles=$(aws eks list-fargate-profiles --cluster-name "$name" --query 'fargateProfileNames' --output text 2>/dev/null)
    for fp in $fargate_profiles; do
        aws eks delete-fargate-profile --cluster-name "$name" --fargate-profile-name "$fp" 2>/dev/null || true
    done

    for fp in $fargate_profiles; do
        aws eks wait fargate-profile-deleted --cluster-name "$name" --fargate-profile-name "$fp" 2>/dev/null || true
    done

    # Delete cluster
    log_step "Deleting EKS cluster..."
    aws eks delete-cluster --name "$name" 2>/dev/null || true
    aws eks wait cluster-deleted --name "$name" 2>/dev/null || true
    log_info "Cluster deleted"

    # Delete VPC
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        log_step "Deleting VPC..."
        # Need to wait for ENIs to be released
        sleep 30
        vpc_delete "$vpc_id" <<< "yes" 2>/dev/null || log_warn "VPC deletion may require manual cleanup"
    fi

    # Delete IAM roles
    log_step "Deleting IAM roles..."
    delete_role_with_policies "${name}-cluster-role" 2>/dev/null || true
    delete_role_with_policies "${name}-node-role" 2>/dev/null || true
    delete_role_with_policies "${name}-fargate-role" 2>/dev/null || true

    # Delete CloudWatch log groups
    log_step "Deleting CloudWatch log groups..."
    aws logs delete-log-group --log-group-name "/aws/eks/$name/cluster" 2>/dev/null || true

    log_success "Destroyed all resources for: $name"
}

status() {
    local name=${1:-}

    log_info "Checking EKS status${name:+ for: $name}..."
    echo ""

    if [ -n "$name" ]; then
        echo -e "${BLUE}=== Cluster ===${NC}"
        aws eks describe-cluster --name "$name" \
            --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
            --output table 2>/dev/null || echo "Cluster not found"

        echo -e "\n${BLUE}=== Node Groups ===${NC}"
        nodegroup_list "$name" 2>/dev/null || echo "No node groups"

        echo -e "\n${BLUE}=== Fargate Profiles ===${NC}"
        fargate_list "$name" 2>/dev/null || echo "No Fargate profiles"

        echo -e "\n${BLUE}=== Add-ons ===${NC}"
        addon_list "$name" 2>/dev/null || echo "No add-ons"

        echo -e "\n${BLUE}=== Nodes (kubectl) ===${NC}"
        aws eks update-kubeconfig --name "$name" --region $(get_region) 2>/dev/null
        kubectl get nodes 2>/dev/null || echo "Unable to connect to cluster"
    else
        echo -e "${BLUE}=== EKS Clusters ===${NC}"
        cluster_list
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
    vpc-delete)
        vpc_delete "$@"
        ;;

    # IAM
    iam-create-cluster-role)
        iam_create_cluster_role "$@"
        ;;
    iam-create-node-role)
        iam_create_node_role "$@"
        ;;
    iam-delete-role)
        iam_delete_role "$@"
        ;;

    # Cluster
    cluster-create)
        cluster_create "$@"
        ;;
    cluster-list)
        cluster_list
        ;;
    cluster-show)
        cluster_show "$@"
        ;;
    cluster-delete)
        cluster_delete "$@"
        ;;
    cluster-update-version)
        cluster_update_version "$@"
        ;;

    # Node Groups
    nodegroup-create)
        nodegroup_create "$@"
        ;;
    nodegroup-list)
        nodegroup_list "$@"
        ;;
    nodegroup-show)
        nodegroup_show "$@"
        ;;
    nodegroup-scale)
        nodegroup_scale "$@"
        ;;
    nodegroup-delete)
        nodegroup_delete "$@"
        ;;

    # Fargate
    fargate-create)
        fargate_create "$@"
        ;;
    fargate-list)
        fargate_list "$@"
        ;;
    fargate-delete)
        fargate_delete "$@"
        ;;

    # Add-ons
    addon-list)
        addon_list "$@"
        ;;
    addon-install)
        addon_install "$@"
        ;;
    addon-delete)
        addon_delete "$@"
        ;;
    addon-available)
        addon_available
        ;;

    # kubectl
    kubeconfig)
        update_kubeconfig "$@"
        ;;
    kubectl-test)
        kubectl_test "$@"
        ;;

    # Sample
    sample-deploy)
        sample_deploy "$@"
        ;;
    sample-delete)
        sample_delete "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
