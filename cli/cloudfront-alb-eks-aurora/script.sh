#!/bin/bash

set -e

# CloudFront → ALB → EKS → Aurora Architecture Script
# Provides operations for managing a Kubernetes-based architecture

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_K8S_VERSION="1.28"
DEFAULT_NODE_TYPE="t3.medium"
DEFAULT_NODE_COUNT=2
DEFAULT_NODE_MIN=1
DEFAULT_NODE_MAX=4
DEFAULT_AURORA_INSTANCE_CLASS="db.t3.medium"

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → ALB → EKS → Aurora Architecture"
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
    echo "ALB (via AWS Load Balancer Controller) Commands:"
    echo "  alb-controller-install <cluster>     - Install AWS Load Balancer Controller"
    echo "  alb-list                             - List Application Load Balancers"
    echo "  ingress-create <cluster> <name> <namespace> <service> <port> - Create ALB Ingress"
    echo "  ingress-delete <cluster> <name> <namespace> - Delete Ingress"
    echo "  ingress-list <cluster> <namespace>   - List Ingresses"
    echo ""
    echo "EKS Commands:"
    echo "  eks-create <name> [version]          - Create EKS cluster"
    echo "  eks-delete <name>                    - Delete EKS cluster"
    echo "  eks-list                             - List EKS clusters"
    echo "  eks-status <name>                    - Show EKS cluster status"
    echo "  eks-kubeconfig <name>                - Update kubeconfig for cluster"
    echo "  nodegroup-create <cluster> <name> [instance-type] [count] - Create node group"
    echo "  nodegroup-delete <cluster> <name>    - Delete node group"
    echo "  nodegroup-list <cluster>             - List node groups"
    echo "  nodegroup-scale <cluster> <name> <min> <max> <desired> - Scale node group"
    echo ""
    echo "Kubernetes Commands:"
    echo "  k8s-deploy <cluster> <name> <image> <port> [replicas] - Deploy application"
    echo "  k8s-delete <cluster> <name> <namespace> - Delete deployment"
    echo "  k8s-scale <cluster> <name> <namespace> <replicas> - Scale deployment"
    echo "  k8s-logs <cluster> <name> <namespace> - View pod logs"
    echo "  k8s-pods <cluster> <namespace>       - List pods"
    echo "  k8s-services <cluster> <namespace>   - List services"
    echo ""
    echo "Aurora Commands:"
    echo "  aurora-create <cluster-id> <username> <password> <subnet-group> <sg-id> - Create Aurora cluster"
    echo "  aurora-delete <cluster-id>           - Delete Aurora cluster"
    echo "  aurora-list                          - List Aurora clusters"
    echo "  aurora-status <cluster-id>           - Show Aurora cluster status"
    echo "  subnet-group-create <name> <subnet-ids> - Create DB subnet group"
    echo "  subnet-group-delete <name>           - Delete DB subnet group"
    echo ""
    echo "ECR Commands:"
    echo "  ecr-create <name>                    - Create ECR repository"
    echo "  ecr-delete <name>                    - Delete ECR repository"
    echo "  ecr-list                             - List ECR repositories"
    echo "  ecr-login                            - Login to ECR"
    echo "  ecr-push <repo> <local-image> <tag>  - Push image to ECR"
    echo ""
    echo "VPC Commands:"
    echo "  vpc-create <name> <cidr>             - Create VPC with subnets"
    echo "  vpc-delete <vpc-id>                  - Delete VPC"
    echo "  vpc-list                             - List VPCs"
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

# Check AWS CLI and kubectl
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Run 'aws configure' first."
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl is not installed. Some commands may not work."
    fi

    if ! command -v eksctl &> /dev/null; then
        log_warn "eksctl is not installed. EKS cluster creation requires eksctl."
        log_warn "Install: https://eksctl.io/installation/"
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

    log_step "Creating VPC for EKS: $name with CIDR $cidr"

    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name},{Key=kubernetes.io/cluster/$name,Value=shared}]" \
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
    azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:3].ZoneName' --output text)
    local az_array=($azs)

    # Create public subnets with EKS tags
    local public_subnets=()
    local private_subnets=()

    for i in 0 1; do
        local public_subnet
        public_subnet=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "10.0.$((i+1)).0/24" \
            --availability-zone "${az_array[$i]}" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public-$((i+1))},{Key=kubernetes.io/cluster/$name,Value=shared},{Key=kubernetes.io/role/elb,Value=1}]" \
            --query 'Subnet.SubnetId' --output text)
        public_subnets+=("$public_subnet")

        local private_subnet
        private_subnet=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "10.0.$((i+11)).0/24" \
            --availability-zone "${az_array[$i]}" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-$((i+1))},{Key=kubernetes.io/cluster/$name,Value=shared},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
            --query 'Subnet.SubnetId' --output text)
        private_subnets+=("$private_subnet")
    done

    log_info "Created public subnets: ${public_subnets[*]}"
    log_info "Created private subnets: ${private_subnets[*]}"

    # Create public route table
    local public_rt
    public_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-public-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route --route-table-id "$public_rt" --destination-cidr-block "0.0.0.0/0" --gateway-id "$igw_id"

    for subnet in "${public_subnets[@]}"; do
        aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$subnet"
        aws ec2 modify-subnet-attribute --subnet-id "$subnet" --map-public-ip-on-launch
    done

    # Create NAT Gateway for private subnets
    log_info "Creating NAT Gateway..."
    local eip_alloc
    eip_alloc=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

    local nat_gw
    nat_gw=$(aws ec2 create-nat-gateway \
        --subnet-id "${public_subnets[0]}" \
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

    for subnet in "${private_subnets[@]}"; do
        aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$subnet"
    done

    log_info "Configured route tables with NAT Gateway"

    echo ""
    echo -e "${GREEN}VPC Created Successfully for EKS${NC}"
    echo "VPC ID: $vpc_id"
    echo "Public Subnets: ${public_subnets[*]}"
    echo "Private Subnets: ${private_subnets[*]}"
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
        aws ec2 release-address --allocation-id "$eip" 2>/dev/null || true
    done

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
# EKS Functions
# ============================================

eks_create() {
    local name=$1
    local version=${2:-$DEFAULT_K8S_VERSION}

    if [ -z "$name" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    if ! command -v eksctl &> /dev/null; then
        log_error "eksctl is required to create EKS clusters"
        log_error "Install: https://eksctl.io/installation/"
        exit 1
    fi

    log_step "Creating EKS cluster: $name (Kubernetes $version)"

    eksctl create cluster \
        --name "$name" \
        --version "$version" \
        --region "$DEFAULT_REGION" \
        --nodegroup-name "${name}-nodes" \
        --node-type "$DEFAULT_NODE_TYPE" \
        --nodes "$DEFAULT_NODE_COUNT" \
        --nodes-min "$DEFAULT_NODE_MIN" \
        --nodes-max "$DEFAULT_NODE_MAX" \
        --managed \
        --with-oidc \
        --alb-ingress-access

    log_info "EKS cluster created successfully"
    log_info "kubeconfig has been updated automatically"
}

eks_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_warn "This will delete EKS cluster: $name and all associated resources"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    if command -v eksctl &> /dev/null; then
        log_step "Deleting EKS cluster using eksctl: $name"
        eksctl delete cluster --name "$name" --region "$DEFAULT_REGION" --wait
    else
        log_step "Deleting EKS cluster using AWS CLI: $name"

        # Delete node groups
        local nodegroups
        nodegroups=$(aws eks list-nodegroups --cluster-name "$name" --query 'nodegroups[]' --output text)
        for ng in $nodegroups; do
            log_info "Deleting node group: $ng"
            aws eks delete-nodegroup --cluster-name "$name" --nodegroup-name "$ng"
            aws eks wait nodegroup-deleted --cluster-name "$name" --nodegroup-name "$ng"
        done

        # Delete cluster
        aws eks delete-cluster --name "$name"
        aws eks wait cluster-deleted --name "$name"
    fi

    log_info "EKS cluster deleted"
}

eks_list() {
    log_info "Listing EKS clusters..."
    aws eks list-clusters --query 'clusters[]' --output table

    echo ""
    local clusters
    clusters=$(aws eks list-clusters --query 'clusters[]' --output text)
    for cluster in $clusters; do
        aws eks describe-cluster --name "$cluster" \
            --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
            --output table
    done
}

eks_status() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_info "EKS cluster status: $name"
    aws eks describe-cluster --name "$name" \
        --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint,RoleArn:roleArn,VpcId:resourcesVpcConfig.vpcId}' \
        --output table

    echo ""
    log_info "Node groups:"
    nodegroup_list "$name"
}

eks_kubeconfig() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_step "Updating kubeconfig for cluster: $name"
    aws eks update-kubeconfig --name "$name" --region "$DEFAULT_REGION"
    log_info "kubeconfig updated"
}

# ============================================
# Node Group Functions
# ============================================

nodegroup_create() {
    local cluster=$1
    local name=$2
    local instance_type=${3:-$DEFAULT_NODE_TYPE}
    local count=${4:-$DEFAULT_NODE_COUNT}

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and node group name are required"
        exit 1
    fi

    if command -v eksctl &> /dev/null; then
        log_step "Creating node group using eksctl: $name"
        eksctl create nodegroup \
            --cluster "$cluster" \
            --name "$name" \
            --node-type "$instance_type" \
            --nodes "$count" \
            --nodes-min "$DEFAULT_NODE_MIN" \
            --nodes-max "$DEFAULT_NODE_MAX" \
            --managed
    else
        log_step "Creating node group using AWS CLI: $name"

        # Get required information
        local subnet_ids
        subnet_ids=$(aws eks describe-cluster --name "$cluster" \
            --query 'cluster.resourcesVpcConfig.subnetIds' --output text | tr '\t' ',')

        local node_role
        node_role=$(aws iam list-roles --query "Roles[?contains(RoleName,'NodeInstanceRole')].Arn|[0]" --output text)

        aws eks create-nodegroup \
            --cluster-name "$cluster" \
            --nodegroup-name "$name" \
            --node-role "$node_role" \
            --subnets ${subnet_ids//,/ } \
            --instance-types "$instance_type" \
            --scaling-config minSize="$DEFAULT_NODE_MIN",maxSize="$DEFAULT_NODE_MAX",desiredSize="$count"
    fi

    log_info "Node group created"
}

nodegroup_delete() {
    local cluster=$1
    local name=$2

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and node group name are required"
        exit 1
    fi

    log_warn "This will delete node group: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting node group: $name"
    aws eks delete-nodegroup --cluster-name "$cluster" --nodegroup-name "$name"
    log_info "Node group deletion initiated"
}

nodegroup_list() {
    local cluster=$1

    if [ -z "$cluster" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_info "Listing node groups for cluster: $cluster"
    local nodegroups
    nodegroups=$(aws eks list-nodegroups --cluster-name "$cluster" --query 'nodegroups[]' --output text)

    for ng in $nodegroups; do
        aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$ng" \
            --query 'nodegroup.{Name:nodegroupName,Status:status,InstanceType:instanceTypes[0],Desired:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize}' \
            --output table
    done
}

nodegroup_scale() {
    local cluster=$1
    local name=$2
    local min=$3
    local max=$4
    local desired=$5

    if [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$desired" ]; then
        log_error "Cluster, node group name, and desired count are required"
        exit 1
    fi

    log_step "Scaling node group: $name"
    aws eks update-nodegroup-config \
        --cluster-name "$cluster" \
        --nodegroup-name "$name" \
        --scaling-config minSize="${min:-$DEFAULT_NODE_MIN}",maxSize="${max:-$DEFAULT_NODE_MAX}",desiredSize="$desired"

    log_info "Node group scaling initiated"
}

# ============================================
# ALB Controller Functions
# ============================================

alb_controller_install() {
    local cluster=$1

    if [ -z "$cluster" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    log_step "Installing AWS Load Balancer Controller on cluster: $cluster"

    local account_id
    account_id=$(get_account_id)

    # Create IAM policy
    log_info "Creating IAM policy..."
    curl -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file:///tmp/iam-policy.json 2>/dev/null || true

    # Create service account
    if command -v eksctl &> /dev/null; then
        log_info "Creating service account with eksctl..."
        eksctl create iamserviceaccount \
            --cluster="$cluster" \
            --namespace=kube-system \
            --name=aws-load-balancer-controller \
            --attach-policy-arn="arn:aws:iam::$account_id:policy/AWSLoadBalancerControllerIAMPolicy" \
            --override-existing-serviceaccounts \
            --approve
    fi

    # Install using Helm
    if command -v helm &> /dev/null; then
        log_info "Installing controller with Helm..."
        helm repo add eks https://aws.github.io/eks-charts
        helm repo update

        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="$cluster" \
            --set serviceAccount.create=false \
            --set serviceAccount.name=aws-load-balancer-controller
    else
        log_warn "Helm not installed. Please install AWS Load Balancer Controller manually."
        log_info "See: https://kubernetes-sigs.github.io/aws-load-balancer-controller/"
    fi

    log_info "AWS Load Balancer Controller installation completed"
}

alb_list() {
    log_info "Listing Application Load Balancers..."
    aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[?Type==`application`].{Name:LoadBalancerName,DNSName:DNSName,State:State.Code}' \
        --output table
}

ingress_create() {
    local cluster=$1
    local name=$2
    local namespace=${3:-default}
    local service=$4
    local port=${5:-80}

    if [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$service" ]; then
        log_error "Cluster, ingress name, and service name are required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_step "Creating ALB Ingress: $name"

    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $name
  namespace: $namespace
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: $service
                port:
                  number: $port
EOF

    log_info "Ingress created. Waiting for ALB to be provisioned..."
    sleep 10
    kubectl get ingress "$name" -n "$namespace"
}

ingress_delete() {
    local cluster=$1
    local name=$2
    local namespace=${3:-default}

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and ingress name are required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_step "Deleting Ingress: $name"
    kubectl delete ingress "$name" -n "$namespace"
    log_info "Ingress deleted"
}

ingress_list() {
    local cluster=$1
    local namespace=${2:-default}

    if [ -z "$cluster" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_info "Listing Ingresses in namespace: $namespace"
    kubectl get ingress -n "$namespace"
}

# ============================================
# Kubernetes Deployment Functions
# ============================================

k8s_deploy() {
    local cluster=$1
    local name=$2
    local image=$3
    local port=${4:-80}
    local replicas=${5:-2}

    if [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$image" ]; then
        log_error "Cluster, deployment name, and image are required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_step "Deploying application: $name"

    # Create deployment
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $name
  template:
    metadata:
      labels:
        app: $name
    spec:
      containers:
        - name: $name
          image: $image
          ports:
            - containerPort: $port
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: $name
spec:
  type: ClusterIP
  ports:
    - port: $port
      targetPort: $port
  selector:
    app: $name
EOF

    log_info "Deployment and service created"
    kubectl get deployment "$name"
    kubectl get service "$name"
}

k8s_delete() {
    local cluster=$1
    local name=$2
    local namespace=${3:-default}

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and deployment name are required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_step "Deleting deployment: $name"
    kubectl delete deployment "$name" -n "$namespace" --ignore-not-found
    kubectl delete service "$name" -n "$namespace" --ignore-not-found
    log_info "Deployment and service deleted"
}

k8s_scale() {
    local cluster=$1
    local name=$2
    local namespace=${3:-default}
    local replicas=$4

    if [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$replicas" ]; then
        log_error "Cluster, deployment name, and replicas are required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_step "Scaling deployment: $name to $replicas replicas"
    kubectl scale deployment "$name" -n "$namespace" --replicas="$replicas"
    log_info "Deployment scaled"
}

k8s_logs() {
    local cluster=$1
    local name=$2
    local namespace=${3:-default}

    if [ -z "$cluster" ] || [ -z "$name" ]; then
        log_error "Cluster and deployment name are required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_info "Fetching logs for deployment: $name"
    kubectl logs -l app="$name" -n "$namespace" --tail=100 -f
}

k8s_pods() {
    local cluster=$1
    local namespace=${2:-default}

    if [ -z "$cluster" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_info "Listing pods in namespace: $namespace"
    kubectl get pods -n "$namespace" -o wide
}

k8s_services() {
    local cluster=$1
    local namespace=${2:-default}

    if [ -z "$cluster" ]; then
        log_error "Cluster name is required"
        exit 1
    fi

    eks_kubeconfig "$cluster"

    log_info "Listing services in namespace: $namespace"
    kubectl get services -n "$namespace"
}

# ============================================
# Aurora Functions
# ============================================

subnet_group_create() {
    local name=$1
    local subnet_ids=$2

    if [ -z "$name" ] || [ -z "$subnet_ids" ]; then
        log_error "Subnet group name and subnet IDs are required"
        exit 1
    fi

    log_step "Creating DB Subnet Group: $name"
    aws rds create-db-subnet-group \
        --db-subnet-group-name "$name" \
        --db-subnet-group-description "Subnet group for $name" \
        --subnet-ids ${subnet_ids//,/ }

    log_info "Created DB Subnet Group"
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

    log_step "Creating Aurora PostgreSQL cluster: $cluster_id"

    local cluster_args="--db-cluster-identifier $cluster_id"
    cluster_args="$cluster_args --engine aurora-postgresql"
    cluster_args="$cluster_args --engine-version 15.4"
    cluster_args="$cluster_args --master-username $username"
    cluster_args="$cluster_args --master-user-password $password"
    cluster_args="$cluster_args --db-subnet-group-name $subnet_group"
    cluster_args="$cluster_args --storage-encrypted"
    cluster_args="$cluster_args --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16"

    if [ -n "$sg_id" ]; then
        cluster_args="$cluster_args --vpc-security-group-ids $sg_id"
    fi

    aws rds create-db-cluster $cluster_args

    # Create instance
    aws rds create-db-instance \
        --db-instance-identifier "${cluster_id}-instance-1" \
        --db-cluster-identifier "$cluster_id" \
        --engine aurora-postgresql \
        --db-instance-class db.serverless

    log_info "Aurora cluster creation initiated"
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

    # Delete instances
    local instances
    instances=$(aws rds describe-db-instances \
        --filters "Name=db-cluster-id,Values=$cluster_id" \
        --query 'DBInstances[].DBInstanceIdentifier' --output text)

    for instance in $instances; do
        aws rds delete-db-instance --db-instance-identifier "$instance" --skip-final-snapshot
    done

    # Wait for instances
    for instance in $instances; do
        aws rds wait db-instance-deleted --db-instance-identifier "$instance" || true
    done

    # Delete cluster
    aws rds delete-db-cluster --db-cluster-identifier "$cluster_id" --skip-final-snapshot
    log_info "Aurora cluster deletion initiated"
}

aurora_list() {
    log_info "Listing Aurora clusters..."
    aws rds describe-db-clusters \
        --query 'DBClusters[].{Cluster:DBClusterIdentifier,Engine:Engine,Status:Status,Endpoint:Endpoint}' \
        --output table
}

aurora_status() {
    local cluster_id=$1

    if [ -z "$cluster_id" ]; then
        log_error "Cluster ID is required"
        exit 1
    fi

    aws rds describe-db-clusters \
        --db-cluster-identifier "$cluster_id" \
        --query 'DBClusters[0].{Cluster:DBClusterIdentifier,Status:Status,Engine:Engine,Endpoint:Endpoint,ReaderEndpoint:ReaderEndpoint}' \
        --output table
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
    "Comment": "CloudFront for EKS $stack_name",
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
    domain_name=$(aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DomainName' --output text)

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

    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)

    local disabled_config
    disabled_config=$(echo "$config" | jq '.Enabled = false')

    aws cloudfront update-distribution --id "$dist_id" --if-match "$etag" --distribution-config "$disabled_config"

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"

    log_info "CloudFront distribution deleted"
}

cf_list() {
    log_info "Listing CloudFront distributions..."
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Enabled:Enabled}' \
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

    log_info "Deploying EKS architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - EKS cluster with managed node group"
    echo "  - AWS Load Balancer Controller"
    echo "  - Aurora PostgreSQL cluster"
    echo "  - CloudFront distribution"
    echo ""
    echo "Prerequisites:"
    echo "  - eksctl installed"
    echo "  - kubectl installed"
    echo "  - helm installed (for ALB controller)"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Step 1: Creating EKS cluster..."
    eks_create "$stack_name"

    log_info "EKS cluster created. Run remaining commands manually:"
    echo "  1. alb-controller-install $stack_name"
    echo "  2. k8s-deploy $stack_name <app-name> <image> <port>"
    echo "  3. ingress-create $stack_name <ingress-name> default <service-name> <port>"
    echo "  4. aurora-create $stack_name-db <username> <password> <subnet-group> <sg-id>"
    echo "  5. cf-create <alb-dns> $stack_name"
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
    echo "  2. Delete Ingress resources"
    echo "  3. Delete Kubernetes deployments"
    echo "  4. Delete EKS cluster (includes nodes)"
    echo "  5. Delete Aurora cluster"
    echo "  6. Delete DB Subnet Group"
    echo "  7. Delete VPC"
    echo ""

    log_info "Use individual delete commands with resource IDs"
}

status() {
    local stack_name=$1

    log_info "Checking status for: $stack_name"
    echo ""

    echo -e "${BLUE}=== EKS Clusters ===${NC}"
    eks_list

    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list

    echo -e "\n${BLUE}=== Aurora Clusters ===${NC}"
    aurora_list

    echo -e "\n${BLUE}=== ECR Repositories ===${NC}"
    ecr_list

    echo -e "\n${BLUE}=== Application Load Balancers ===${NC}"
    alb_list
}

# ============================================
# Main Script Logic
# ============================================

check_prerequisites

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status "$@" ;;

    # VPC
    vpc-create) vpc_create "$@" ;;
    vpc-delete) vpc_delete "$@" ;;
    vpc-list) vpc_list ;;

    # ECR
    ecr-create) ecr_create "$@" ;;
    ecr-delete) ecr_delete "$@" ;;
    ecr-list) ecr_list ;;
    ecr-login) ecr_login ;;
    ecr-push) ecr_push "$@" ;;

    # EKS
    eks-create) eks_create "$@" ;;
    eks-delete) eks_delete "$@" ;;
    eks-list) eks_list ;;
    eks-status) eks_status "$@" ;;
    eks-kubeconfig) eks_kubeconfig "$@" ;;

    # Node Groups
    nodegroup-create) nodegroup_create "$@" ;;
    nodegroup-delete) nodegroup_delete "$@" ;;
    nodegroup-list) nodegroup_list "$@" ;;
    nodegroup-scale) nodegroup_scale "$@" ;;

    # ALB Controller
    alb-controller-install) alb_controller_install "$@" ;;
    alb-list) alb_list ;;
    ingress-create) ingress_create "$@" ;;
    ingress-delete) ingress_delete "$@" ;;
    ingress-list) ingress_list "$@" ;;

    # Kubernetes
    k8s-deploy) k8s_deploy "$@" ;;
    k8s-delete) k8s_delete "$@" ;;
    k8s-scale) k8s_scale "$@" ;;
    k8s-logs) k8s_logs "$@" ;;
    k8s-pods) k8s_pods "$@" ;;
    k8s-services) k8s_services "$@" ;;

    # Aurora
    aurora-create) aurora_create "$@" ;;
    aurora-delete) aurora_delete "$@" ;;
    aurora-list) aurora_list ;;
    aurora-status) aurora_status "$@" ;;
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
