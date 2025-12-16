#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# EC2 → VPC Endpoint → S3 Architecture Script
# EC2インスタンスをプライベートサブネットに配置し、VPC Endpointを介してS3にアクセス
# Session Managerを使用してEC2にアクセス（SSHなし、パブリックIPなし）
# NAT Instance経由でインターネットアクセス（Git等）を可能にする
#
# コスト最小化設計:
# - S3 VPC Endpoint: Gatewayタイプ（無料）
# - SSM VPC Endpoints: Interfaceタイプ（最小限の3つ）
# - EC2: t3.micro（無料枠対象）
# - NAT Instance: t4g.nano（月額~$3、NAT Gatewayの代替）
# - パブリックIP: NAT Instanceのみ

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_INSTANCE_TYPE="t3.micro"
DEFAULT_NAT_INSTANCE_TYPE="t4g.nano"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_PUBLIC_SUBNET_CIDR="10.0.0.0/24"
DEFAULT_PRIVATE_SUBNET_CIDR="10.0.1.0/24"

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "EC2 (Private) → VPC Endpoint → S3 Architecture"
    echo "Session Manager経由でEC2にアクセスし、VPC Endpoint経由でS3にアクセス"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name> [bucket-name]    - Deploy full architecture"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status [stack-name]                  - Show status of all components"
    echo ""
    echo "VPC Commands:"
    echo "  vpc-create <name> [cidr]             - Create VPC with private subnet"
    echo "  vpc-delete <vpc-id>                  - Delete VPC and associated resources"
    echo "  vpc-list                             - List VPCs"
    echo ""
    echo "VPC Endpoint Commands:"
    echo "  endpoint-s3-create <vpc-id> <route-table-id>  - Create S3 Gateway Endpoint"
    echo "  endpoint-ssm-create <vpc-id> <subnet-id> <sg-id> - Create SSM Interface Endpoints"
    echo "  endpoint-delete <endpoint-id>        - Delete VPC Endpoint"
    echo "  endpoint-list [vpc-id]               - List VPC Endpoints"
    echo ""
    echo "NAT Instance Commands:"
    echo "  nat-create <name> <subnet-id> <sg-id> [instance-type] - Create NAT Instance"
    echo "  nat-delete <instance-id>             - Delete NAT Instance"
    echo "  nat-list                             - List NAT Instances"
    echo "  nat-sg-create <name> <vpc-id>        - Create Security Group for NAT"
    echo ""
    echo "Security Group Commands:"
    echo "  sg-create <name> <vpc-id>            - Create Security Group for EC2"
    echo "  sg-delete <sg-id>                    - Delete Security Group"
    echo ""
    echo "IAM Commands:"
    echo "  role-create <name>                   - Create IAM Role for EC2 (SSM + S3)"
    echo "  role-delete <name>                   - Delete IAM Role"
    echo ""
    echo "EC2 Commands:"
    echo "  ec2-create <name> <subnet-id> <sg-id> <instance-profile> - Create EC2 instance"
    echo "  ec2-delete <instance-id>             - Terminate EC2 instance"
    echo "  ec2-list                             - List EC2 instances"
    echo "  ec2-connect <instance-id>            - Connect via Session Manager"
    echo ""
    echo "S3 Commands:"
    echo "  s3-create <bucket-name>              - Create S3 bucket"
    echo "  s3-delete <bucket-name>              - Delete S3 bucket"
    echo "  s3-list                              - List S3 buckets"
    echo ""
    echo "Examples:"
    echo "  $0 deploy my-stack                   - Deploy with auto-generated bucket name"
    echo "  $0 deploy my-stack my-bucket         - Deploy with specific bucket name"
    echo "  $0 ec2-connect i-1234567890abcdef0   - Connect to EC2 via Session Manager"
    echo "  $0 status my-stack                   - Check deployment status"
    echo ""
    exit 1
}

# ============================================
# VPC Functions
# ============================================

vpc_create() {
    local name=$1
    local cidr=${2:-$DEFAULT_VPC_CIDR}

    if [ -z "$name" ]; then
        log_error "VPC name is required"
        exit 1
    fi

    log_step "Creating VPC: $name with CIDR $cidr"

    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name},{Key=Stack,Value=$name}]" \
        --query 'Vpc.VpcId' --output text)

    log_info "Created VPC: $vpc_id"

    # Enable DNS hostnames and DNS support (required for VPC Endpoints)
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support

    # Get first AZ
    local az
    az=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)

    # Create Internet Gateway
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$name-igw},{Key=Stack,Value=$name}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)

    aws ec2 attach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
    log_info "Created and attached Internet Gateway: $igw_id"

    # Create public subnet (for NAT Instance)
    local public_subnet
    public_subnet=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$DEFAULT_PUBLIC_SUBNET_CIDR" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-public},{Key=Stack,Value=$name}]" \
        --query 'Subnet.SubnetId' --output text)

    log_info "Created public subnet: $public_subnet in $az"

    # Create route table for public subnet
    local public_rt
    public_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-public-rt},{Key=Stack,Value=$name}]" \
        --query 'RouteTable.RouteTableId' --output text)

    # Add route to IGW for internet access
    aws ec2 create-route \
        --route-table-id "$public_rt" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id" > /dev/null

    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet" > /dev/null
    log_info "Created public route table: $public_rt (with IGW route)"

    # Create private subnet (no public IP, no direct IGW route)
    local private_subnet
    private_subnet=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$DEFAULT_PRIVATE_SUBNET_CIDR" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private},{Key=Stack,Value=$name}]" \
        --query 'Subnet.SubnetId' --output text)

    log_info "Created private subnet: $private_subnet in $az"

    # Create route table for private subnet
    local private_rt
    private_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-private-rt},{Key=Stack,Value=$name}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 associate-route-table --route-table-id "$private_rt" --subnet-id "$private_subnet" > /dev/null

    log_info "Created and associated route table: $private_rt"

    echo ""
    echo -e "${GREEN}VPC Created Successfully${NC}"
    echo "VPC ID: $vpc_id"
    echo "Internet Gateway: $igw_id"
    echo "Public Subnet: $public_subnet (for NAT Instance)"
    echo "Private Subnet: $private_subnet (for EC2)"
    echo "Public Route Table: $public_rt"
    echo "Private Route Table: $private_rt"
    echo "Availability Zone: $az"
    echo ""
    echo "Next steps:"
    echo "  1. Create NAT security group: $0 nat-sg-create $name-nat-sg $vpc_id"
    echo "  2. Create NAT instance: $0 nat-create $name-nat $public_subnet <nat-sg-id>"
    echo "  3. Create EC2 security group: $0 sg-create $name-sg $vpc_id"
    echo "  4. Create S3 endpoint: $0 endpoint-s3-create $vpc_id $private_rt"
    echo "  5. Create SSM endpoints: $0 endpoint-ssm-create $vpc_id $private_subnet <sg-id>"
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

    # Delete VPC Endpoints first
    local endpoints
    endpoints=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null)
    for endpoint in $endpoints; do
        log_info "Deleting VPC Endpoint: $endpoint"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$endpoint" 2>/dev/null || true
    done

    # Wait for endpoints to be deleted
    if [ -n "$endpoints" ]; then
        log_info "Waiting for VPC Endpoints to be deleted..."
        sleep 10
    fi

    # Terminate EC2 instances
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
    for instance in $instances; do
        log_info "Terminating EC2 instance: $instance"
        aws ec2 terminate-instances --instance-ids "$instance" 2>/dev/null || true
    done

    # Wait for instances to terminate
    if [ -n "$instances" ]; then
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids $instances 2>/dev/null || true
    fi

    # Delete subnets
    local subnets
    subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text)
    for subnet in $subnets; do
        log_info "Deleting subnet: $subnet"
        aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
    done

    # Delete route tables (except main)
    local route_tables
    route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for rt in $route_tables; do
        log_info "Deleting route table: $rt"
        aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
    done

    # Delete security groups (except default)
    local security_groups
    security_groups=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for sg in $security_groups; do
        log_info "Deleting security group: $sg"
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    # Detach and delete Internet Gateway
    local igw_ids
    igw_ids=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[].InternetGatewayId' --output text)
    for igw in $igw_ids; do
        log_info "Detaching and deleting Internet Gateway: $igw"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id" 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" 2>/dev/null || true
    done

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id"
    log_success "VPC deleted successfully"
}

vpc_list() {
    log_info "Listing VPCs..."
    aws ec2 describe-vpcs \
        --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],State:State}' \
        --output table
}

# ============================================
# VPC Endpoint Functions
# ============================================

endpoint_s3_create() {
    local vpc_id=$1
    local route_table_id=$2

    if [ -z "$vpc_id" ] || [ -z "$route_table_id" ]; then
        log_error "VPC ID and Route Table ID are required"
        exit 1
    fi

    local region=$(get_region)
    log_step "Creating S3 Gateway Endpoint in VPC: $vpc_id"

    # Check if endpoint already exists
    local existing
    existing=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=service-name,Values=com.amazonaws.$region.s3" \
        --query 'VpcEndpoints[0].VpcEndpointId' --output text 2>/dev/null)

    if [ -n "$existing" ] && [ "$existing" != "None" ]; then
        log_warn "S3 VPC Endpoint already exists: $existing"
        echo "$existing"
        return 0
    fi

    local endpoint_id
    endpoint_id=$(aws ec2 create-vpc-endpoint \
        --vpc-id "$vpc_id" \
        --service-name "com.amazonaws.$region.s3" \
        --route-table-ids "$route_table_id" \
        --vpc-endpoint-type Gateway \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=s3-gateway-endpoint}]" \
        --query 'VpcEndpoint.VpcEndpointId' --output text)

    log_success "Created S3 Gateway Endpoint: $endpoint_id (無料)"
    echo "$endpoint_id"
}

endpoint_ssm_create() {
    local vpc_id=$1
    local subnet_id=$2
    local sg_id=$3

    if [ -z "$vpc_id" ] || [ -z "$subnet_id" ] || [ -z "$sg_id" ]; then
        log_error "VPC ID, Subnet ID, and Security Group ID are required"
        exit 1
    fi

    local region=$(get_region)
    log_step "Creating SSM Interface Endpoints in VPC: $vpc_id"

    # SSM requires 3 endpoints for Session Manager: ssm, ssmmessages, ec2messages
    local services=("ssm" "ssmmessages" "ec2messages")

    for service in "${services[@]}"; do
        local service_name="com.amazonaws.$region.$service"

        # Check if endpoint already exists
        local existing
        existing=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=service-name,Values=$service_name" \
            --query 'VpcEndpoints[0].VpcEndpointId' --output text 2>/dev/null)

        if [ -n "$existing" ] && [ "$existing" != "None" ]; then
            log_warn "$service VPC Endpoint already exists: $existing"
            continue
        fi

        log_info "Creating $service endpoint..."
        local endpoint_id
        endpoint_id=$(aws ec2 create-vpc-endpoint \
            --vpc-id "$vpc_id" \
            --service-name "$service_name" \
            --subnet-ids "$subnet_id" \
            --security-group-ids "$sg_id" \
            --vpc-endpoint-type Interface \
            --private-dns-enabled \
            --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$service-endpoint}]" \
            --query 'VpcEndpoint.VpcEndpointId' --output text)

        log_info "Created $service endpoint: $endpoint_id"
    done

    log_success "SSM Interface Endpoints created"
    log_warn "Interface Endpoints have hourly charges (~\$0.01/hr/endpoint)"
}

endpoint_delete() {
    local endpoint_id=$1

    if [ -z "$endpoint_id" ]; then
        log_error "Endpoint ID is required"
        exit 1
    fi

    log_step "Deleting VPC Endpoint: $endpoint_id"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$endpoint_id"
    log_success "VPC Endpoint deleted"
}

endpoint_list() {
    local vpc_id=$1

    log_info "Listing VPC Endpoints..."

    local filter_args=""
    if [ -n "$vpc_id" ]; then
        filter_args="--filters Name=vpc-id,Values=$vpc_id"
    fi

    aws ec2 describe-vpc-endpoints $filter_args \
        --query 'VpcEndpoints[].{EndpointId:VpcEndpointId,ServiceName:ServiceName,Type:VpcEndpointType,State:State,VpcId:VpcId}' \
        --output table
}

# ============================================
# Security Group Functions
# ============================================

sg_create() {
    local name=$1
    local vpc_id=$2

    if [ -z "$name" ] || [ -z "$vpc_id" ]; then
        log_error "Security group name and VPC ID are required"
        exit 1
    fi

    log_step "Creating Security Group: $name"

    # Create security group
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "Security group for EC2 with VPC Endpoint access" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name}]" \
        --query 'GroupId' --output text)

    log_info "Created security group: $sg_id"

    # Get VPC CIDR for internal traffic
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --query 'Vpcs[0].CidrBlock' --output text)

    # Allow HTTPS (443) from VPC CIDR for VPC Endpoints
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr "$vpc_cidr" \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=vpc-endpoint-https}]"

    log_info "Added inbound rule: HTTPS (443) from $vpc_cidr"

    # Allow all outbound (default, but explicit)
    # Default egress rule allows all outbound traffic

    echo ""
    echo -e "${GREEN}Security Group Created${NC}"
    echo "Security Group ID: $sg_id"
    echo "Inbound Rules:"
    echo "  - HTTPS (443) from $vpc_cidr (for VPC Endpoints)"
    echo "Outbound Rules:"
    echo "  - All traffic (default)"
    echo ""
    echo "$sg_id"
}

sg_delete() {
    local sg_id=$1

    if [ -z "$sg_id" ]; then
        log_error "Security Group ID is required"
        exit 1
    fi

    log_step "Deleting Security Group: $sg_id"
    aws ec2 delete-security-group --group-id "$sg_id"
    log_success "Security Group deleted"
}

# ============================================
# IAM Role Functions
# ============================================

role_create() {
    local role_name=$1

    if [ -z "$role_name" ]; then
        log_error "Role name is required"
        exit 1
    fi

    log_step "Creating IAM Role: $role_name"

    # Trust policy for EC2
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

    # Create role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" \
        --description "Role for EC2 with SSM and S3 access" \
        --tags Key=Name,Value="$role_name" 2>/dev/null || {
            log_warn "Role already exists or creation failed"
        }

    # Attach SSM managed policy (required for Session Manager)
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true

    log_info "Attached AmazonSSMManagedInstanceCore policy"

    # Attach S3 read-only policy (minimal permissions for S3 access)
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 2>/dev/null || true

    log_info "Attached AmazonS3ReadOnlyAccess policy"

    # Create instance profile
    local profile_name="$role_name-profile"
    aws iam create-instance-profile \
        --instance-profile-name "$profile_name" 2>/dev/null || {
            log_warn "Instance profile already exists"
        }

    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" 2>/dev/null || true

    log_info "Created instance profile: $profile_name"

    # Wait for IAM propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10

    echo ""
    echo -e "${GREEN}IAM Role Created${NC}"
    echo "Role Name: $role_name"
    echo "Instance Profile: $profile_name"
    echo "Attached Policies:"
    echo "  - AmazonSSMManagedInstanceCore (Session Manager)"
    echo "  - AmazonS3ReadOnlyAccess (S3 read access)"
}

role_delete() {
    local role_name=$1

    if [ -z "$role_name" ]; then
        log_error "Role name is required"
        exit 1
    fi

    log_step "Deleting IAM Role: $role_name"

    local profile_name="$role_name-profile"

    # Remove role from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" 2>/dev/null || true

    # Delete instance profile
    aws iam delete-instance-profile \
        --instance-profile-name "$profile_name" 2>/dev/null || true

    log_info "Deleted instance profile: $profile_name"

    # Detach policies
    local policies
    policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)
    for policy in $policies; do
        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy" 2>/dev/null || true
        log_info "Detached policy: $policy"
    done

    # Delete role
    aws iam delete-role --role-name "$role_name" 2>/dev/null || true

    log_success "IAM Role deleted: $role_name"
}

# ============================================
# NAT Instance Functions
# ============================================

nat_sg_create() {
    local name=$1
    local vpc_id=$2

    if [ -z "$name" ] || [ -z "$vpc_id" ]; then
        log_error "Security group name and VPC ID are required"
        exit 1
    fi

    log_step "Creating Security Group for NAT Instance: $name"

    # Create security group
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "Security group for NAT Instance" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name}]" \
        --query 'GroupId' --output text)

    log_info "Created security group: $sg_id"

    # Get VPC CIDR for internal traffic
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --query 'Vpcs[0].CidrBlock' --output text)

    # Allow HTTP (80) from private subnet for package updates
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr "$vpc_cidr" \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=http-from-private}]"

    log_info "Added inbound rule: HTTP (80) from $vpc_cidr"

    # Allow HTTPS (443) from private subnet for Git, npm, etc.
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr "$vpc_cidr" \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=https-from-private}]"

    log_info "Added inbound rule: HTTPS (443) from $vpc_cidr"

    # Allow ICMP (ping) from private subnet for connectivity testing
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol icmp \
        --port -1 \
        --cidr "$vpc_cidr" \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=icmp-from-private}]"

    log_info "Added inbound rule: ICMP (all) from $vpc_cidr"

    echo ""
    echo -e "${GREEN}NAT Security Group Created${NC}"
    echo "Security Group ID: $sg_id"
    echo "Inbound Rules:"
    echo "  - HTTP (80) from $vpc_cidr (for package updates)"
    echo "  - HTTPS (443) from $vpc_cidr (for Git, npm, etc.)"
    echo "  - ICMP (all) from $vpc_cidr (for ping)"
    echo "Outbound Rules:"
    echo "  - All traffic (default)"
    echo ""
    echo "$sg_id"
}

nat_instance_create() {
    local name=$1
    local subnet_id=$2
    local sg_id=$3
    local instance_type=${4:-$DEFAULT_NAT_INSTANCE_TYPE}

    if [ -z "$name" ] || [ -z "$subnet_id" ] || [ -z "$sg_id" ]; then
        log_error "Name, Subnet ID, and Security Group ID are required"
        exit 1
    fi

    log_step "Creating NAT Instance: $name (Type: $instance_type)"

    # Get latest Amazon Linux 2023 AMI for ARM (t4g) or x86 (t3)
    local ami_param
    if [[ "$instance_type" == t4g.* ]] || [[ "$instance_type" == t3g.* ]]; then
        ami_param="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    else
        ami_param="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    fi

    local ami_id
    ami_id=$(aws ssm get-parameter \
        --name "$ami_param" \
        --query 'Parameter.Value' --output text)

    log_info "Using AMI: $ami_id (Amazon Linux 2023)"

    # User data script to configure NAT
    local user_data='#!/bin/bash
# Configure as NAT instance
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

# Configure iptables for NAT
/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Flush FORWARD chain and set ACCEPT policy
/sbin/iptables -F FORWARD
/sbin/iptables -P FORWARD ACCEPT

# Explicitly allow forwarding from VPC
/sbin/iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# Persist iptables rules
mkdir -p /etc/sysconfig
iptables-save > /etc/sysconfig/iptables

# Create systemd service to restore iptables on boot
cat > /etc/systemd/system/iptables-restore.service << EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore /etc/sysconfig/iptables

[Install]
WantedBy=multi-user.target
EOF

systemctl enable iptables-restore.service
'

    # Create NAT instance
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --subnet-id "$subnet_id" \
        --security-group-ids "$sg_id" \
        --associate-public-ip-address \
        --user-data "$user_data" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name},{Key=Role,Value=NAT}]" \
        --metadata-options "HttpEndpoint=enabled,HttpTokens=required" \
        --query 'Instances[0].InstanceId' --output text)

    log_info "Created NAT instance: $instance_id"
    log_info "Waiting for instance to be running..."

    aws ec2 wait instance-running --instance-ids "$instance_id"

    # Disable source/destination check (required for NAT)
    aws ec2 modify-instance-attribute \
        --instance-id "$instance_id" \
        --no-source-dest-check

    log_info "Disabled source/destination check"

    # Get public and private IPs
    local public_ip
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

    local private_ip
    private_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

    echo ""
    echo -e "${GREEN}NAT Instance Created${NC}"
    echo "Instance ID: $instance_id"
    echo "Instance Type: $instance_type"
    echo "Private IP: $private_ip"
    echo "Public IP: $public_ip"
    echo "Source/Dest Check: Disabled (required for NAT)"
    echo ""
    echo "Cost estimate: ~\$3/month (t4g.nano) or ~\$4/month (t3.nano)"
    echo ""
    echo "Next: Add route to private subnet route table:"
    echo "  aws ec2 create-route --route-table-id <private-rt-id> \\"
    echo "    --destination-cidr-block 0.0.0.0/0 --instance-id $instance_id"
    echo ""
    echo "$instance_id"
}

nat_instance_delete() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        log_error "Instance ID is required"
        exit 1
    fi

    log_warn "This will terminate NAT instance: $instance_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Terminating NAT instance: $instance_id"
    aws ec2 terminate-instances --instance-ids "$instance_id"

    log_info "Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids "$instance_id"

    log_success "NAT instance terminated"
}

nat_instance_list() {
    log_info "Listing NAT instances..."
    aws ec2 describe-instances \
        --filters "Name=tag:Role,Values=NAT" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].{InstanceId:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' \
        --output table
}

# ============================================
# EC2 Functions
# ============================================

ec2_create() {
    local name=$1
    local subnet_id=$2
    local sg_id=$3
    local instance_profile=$4
    local instance_type=${5:-$DEFAULT_INSTANCE_TYPE}

    if [ -z "$name" ] || [ -z "$subnet_id" ] || [ -z "$sg_id" ] || [ -z "$instance_profile" ]; then
        log_error "Name, Subnet ID, Security Group ID, and Instance Profile are required"
        exit 1
    fi

    log_step "Creating EC2 instance: $name"

    # Get latest Amazon Linux 2023 AMI
    local ami_id
    ami_id=$(aws ssm get-parameter \
        --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
        --query 'Parameter.Value' --output text)

    log_info "Using AMI: $ami_id (Amazon Linux 2023)"

    # Create instance (no public IP, private subnet only)
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --subnet-id "$subnet_id" \
        --security-group-ids "$sg_id" \
        --iam-instance-profile Name="$instance_profile" \
        --no-associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name}]" \
        --metadata-options "HttpEndpoint=enabled,HttpTokens=required" \
        --query 'Instances[0].InstanceId' --output text)

    log_info "Created EC2 instance: $instance_id"
    log_info "Waiting for instance to be running..."

    aws ec2 wait instance-running --instance-ids "$instance_id"

    # Wait additional time for SSM agent to initialize
    log_info "Waiting for SSM agent to initialize (30 seconds)..."
    sleep 30

    # Get private IP
    local private_ip
    private_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

    echo ""
    echo -e "${GREEN}EC2 Instance Created${NC}"
    echo "Instance ID: $instance_id"
    echo "Private IP: $private_ip"
    echo "Instance Type: $instance_type"
    echo "Public IP: None (private subnet)"
    echo ""
    echo "To connect via Session Manager:"
    echo "  aws ssm start-session --target $instance_id"
    echo "  or"
    echo "  $0 ec2-connect $instance_id"
    echo ""
    echo "Test S3 access from EC2:"
    echo "  aws s3 ls"
}

ec2_delete() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        log_error "Instance ID is required"
        exit 1
    fi

    log_warn "This will terminate EC2 instance: $instance_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Terminating EC2 instance: $instance_id"
    aws ec2 terminate-instances --instance-ids "$instance_id"

    log_info "Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids "$instance_id"

    log_success "EC2 instance terminated"
}

ec2_list() {
    log_info "Listing EC2 instances..."
    aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].{InstanceId:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' \
        --output table
}

ec2_connect() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        log_error "Instance ID is required"
        exit 1
    fi

    # Check if session-manager-plugin is installed
    if ! command -v session-manager-plugin &> /dev/null; then
        log_error "Session Manager plugin is not installed"
        echo ""
        echo "Install instructions:"
        echo "  macOS: brew install --cask session-manager-plugin"
        echo "  Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        exit 1
    fi

    log_info "Connecting to instance: $instance_id via Session Manager"
    aws ssm start-session --target "$instance_id"
}

# ============================================
# S3 Functions
# ============================================

s3_create() {
    local bucket_name=$1

    if [ -z "$bucket_name" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    local region=$(get_region)
    log_step "Creating S3 bucket: $bucket_name"

    # Create bucket
    if [ "$region" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$region" \
            --create-bucket-configuration LocationConstraint="$region"
    fi

    # Block public access
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    log_info "Blocked public access"

    # Enable versioning (optional but recommended)
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    log_info "Enabled versioning"

    echo ""
    echo -e "${GREEN}S3 Bucket Created${NC}"
    echo "Bucket Name: $bucket_name"
    echo "Region: $region"
    echo "Public Access: Blocked"
    echo "Versioning: Enabled"
}

s3_delete() {
    local bucket_name=$1

    if [ -z "$bucket_name" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_warn "This will delete S3 bucket and all contents: $bucket_name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting S3 bucket: $bucket_name"

    # Delete all objects (including versions)
    aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true

    # Delete all versions
    aws s3api delete-objects \
        --bucket "$bucket_name" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$bucket_name" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
            --output json 2>/dev/null)" 2>/dev/null || true

    # Delete all delete markers
    aws s3api delete-objects \
        --bucket "$bucket_name" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$bucket_name" \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            --output json 2>/dev/null)" 2>/dev/null || true

    # Delete bucket
    aws s3api delete-bucket --bucket "$bucket_name"

    log_success "S3 bucket deleted"
}

s3_list() {
    log_info "Listing S3 buckets..."
    aws s3api list-buckets \
        --query 'Buckets[].{Name:Name,Created:CreationDate}' \
        --output table
}

# ============================================
# Full Stack Deploy/Destroy
# ============================================

deploy() {
    local stack_name=$1
    local bucket_name=${2:-"$stack_name-bucket-$(date +%s)"}

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_info "Deploying EC2 + NAT Instance + VPC Endpoint + S3 architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets"
    echo "  - Internet Gateway"
    echo "  - NAT Instance (t4g.nano) in public subnet"
    echo "  - S3 Gateway VPC Endpoint (無料)"
    echo "  - SSM Interface VPC Endpoints x3 (有料: ~\$0.01/hr/endpoint)"
    echo "  - Security Groups (NAT + EC2)"
    echo "  - IAM Role with SSM + S3 permissions"
    echo "  - EC2 instance (t3.micro - 無料枠対象) in private subnet"
    echo "  - S3 bucket"
    echo ""
    echo -e "${YELLOW}Estimated cost (excluding free tier):${NC}"
    echo "  - NAT Instance (t4g.nano): ~\$3/month"
    echo "  - VPC Endpoints (Interface): ~\$22/month (3 endpoints)"
    echo "  - EC2 (if not in free tier): ~\$8/month"
    echo "  - S3: Pay per usage"
    echo "  - Total: ~\$33/month (without free tier)"
    echo ""
    echo -e "${GREEN}Cost savings vs NAT Gateway:${NC}"
    echo "  - NAT Gateway: ~\$32/month + data transfer"
    echo "  - NAT Instance: ~\$3/month (10x cheaper!)"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    log_step "Step 1/10: Creating VPC with public and private subnets..."
    vpc_create "$stack_name" 2>&1 | head -30

    # Get VPC ID
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' --output text)

    # Get public subnet ID
    local public_subnet_id
    public_subnet_id=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$stack_name-public" \
        --query 'Subnets[0].SubnetId' --output text)

    # Get private subnet ID
    local private_subnet_id
    private_subnet_id=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$stack_name-private" \
        --query 'Subnets[0].SubnetId' --output text)

    # Get private route table ID
    local private_route_table_id
    private_route_table_id=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$stack_name-private-rt" \
        --query 'RouteTables[0].RouteTableId' --output text)

    echo ""
    log_step "Step 2/10: Creating NAT Security Group..."
    nat_sg_create "$stack_name-nat-sg" "$vpc_id" > /dev/null

    # Get NAT security group ID by tag
    local nat_sg_id
    nat_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$stack_name-nat-sg" \
        --query 'SecurityGroups[0].GroupId' --output text)

    if [ -z "$nat_sg_id" ] || [ "$nat_sg_id" = "None" ]; then
        log_error "Failed to create NAT security group"
        exit 1
    fi

    log_success "NAT Security Group: $nat_sg_id"

    echo ""
    log_step "Step 3/10: Creating NAT Instance..."
    nat_instance_create "$stack_name-nat" "$public_subnet_id" "$nat_sg_id" "$DEFAULT_NAT_INSTANCE_TYPE"

    # Get NAT instance ID by tag (wait a moment for instance to be tagged)
    log_info "Retrieving NAT instance ID..."
    sleep 2
    local nat_instance_id
    nat_instance_id=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$stack_name-nat" "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text)

    if [ -z "$nat_instance_id" ] || [ "$nat_instance_id" = "None" ]; then
        log_error "Failed to retrieve NAT instance ID"
        exit 1
    fi

    log_success "NAT Instance ID: $nat_instance_id"

    echo ""
    log_step "Step 4/10: Adding NAT route to private subnet..."
    aws ec2 create-route \
        --route-table-id "$private_route_table_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --instance-id "$nat_instance_id" > /dev/null
    log_success "Added route: 0.0.0.0/0 -> NAT Instance ($nat_instance_id)"

    echo ""
    log_step "Step 5/10: Creating EC2 Security Group..."
    sg_create "$stack_name-sg" "$vpc_id" > /dev/null

    # Get EC2 security group ID by tag
    local ec2_sg_id
    ec2_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=$stack_name-sg" \
        --query 'SecurityGroups[0].GroupId' --output text)

    if [ -z "$ec2_sg_id" ] || [ "$ec2_sg_id" = "None" ]; then
        log_error "Failed to create EC2 security group"
        exit 1
    fi

    log_success "EC2 Security Group: $ec2_sg_id"

    echo ""
    log_step "Step 6/10: Creating S3 Gateway Endpoint (無料)..."
    endpoint_s3_create "$vpc_id" "$private_route_table_id" > /dev/null

    echo ""
    log_step "Step 7/10: Creating SSM Interface Endpoints..."
    endpoint_ssm_create "$vpc_id" "$private_subnet_id" "$ec2_sg_id" > /dev/null

    echo ""
    log_step "Step 8/10: Creating IAM Role..."
    role_create "$stack_name-role" > /dev/null

    echo ""
    log_step "Step 9/10: Creating S3 Bucket..."
    s3_create "$bucket_name" > /dev/null

    echo ""
    log_step "Step 10/10: Creating EC2 Instance..."
    ec2_create "$stack_name-ec2" "$private_subnet_id" "$ec2_sg_id" "$stack_name-role-profile"

    # Get instance ID
    local instance_id
    instance_id=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$stack_name-ec2" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text)

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Resources created:"
    echo "  VPC: $vpc_id"
    echo "  Public Subnet: $public_subnet_id (NAT Instance)"
    echo "  Private Subnet: $private_subnet_id (EC2)"
    echo "  NAT Instance: $nat_instance_id (t4g.nano)"
    echo "  EC2 Instance: $instance_id (t3.micro)"
    echo "  S3 Bucket: $bucket_name"
    echo ""
    echo "Connect to EC2 via Session Manager:"
    echo "  aws ssm start-session --target $instance_id"
    echo ""
    echo "Test internet access from EC2 (via NAT Instance):"
    echo "  (Inside EC2) ping -c 3 8.8.8.8"
    echo "  (Inside EC2) curl -I https://github.com"
    echo "  (Inside EC2) git clone https://github.com/user/repo"
    echo ""
    echo "Test S3 access from EC2 (via VPC Endpoint):"
    echo "  (Inside EC2) aws s3 ls"
    echo "  (Inside EC2) aws s3 ls s3://$bucket_name"
    echo ""
    echo "Monthly cost estimate (without free tier):"
    echo "  NAT Instance: ~\$3, VPC Endpoints: ~\$22, EC2: ~\$8"
    echo "  Total: ~\$33/month"
    echo ""
    echo "Cleanup:"
    echo "  $0 destroy $stack_name"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_warn "This will destroy ALL resources for stack: $stack_name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - EC2 instance (private subnet)"
    echo "  - NAT instance (public subnet)"
    echo "  - S3 bucket (and contents)"
    echo "  - IAM role and instance profile"
    echo "  - VPC Endpoints"
    echo "  - Security Groups"
    echo "  - Internet Gateway"
    echo "  - VPC and subnets"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Get VPC ID
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

    echo ""
    log_step "Step 1/7: Terminating EC2 instances..."
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$stack_name-ec2" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
    for instance in $instances; do
        log_info "Terminating EC2: $instance"
        aws ec2 terminate-instances --instance-ids "$instance" 2>/dev/null || true
    done
    if [ -n "$instances" ]; then
        aws ec2 wait instance-terminated --instance-ids $instances 2>/dev/null || true
    fi

    echo ""
    log_step "Step 2/7: Terminating NAT instances..."
    local nat_instances
    nat_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$stack_name-nat" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
    for instance in $nat_instances; do
        log_info "Terminating NAT: $instance"
        aws ec2 terminate-instances --instance-ids "$instance" 2>/dev/null || true
    done
    if [ -n "$nat_instances" ]; then
        aws ec2 wait instance-terminated --instance-ids $nat_instances 2>/dev/null || true
    fi

    echo ""
    log_step "Step 3/7: Deleting S3 bucket..."
    # Find bucket by stack name pattern
    local buckets
    buckets=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$stack_name-bucket')].Name" --output text 2>/dev/null)
    for bucket in $buckets; do
        log_info "Deleting bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
    done

    echo ""
    log_step "Step 4/7: Deleting IAM Role..."
    role_delete "$stack_name-role" 2>/dev/null || true

    echo ""
    log_step "Step 5/7: Deleting VPC Endpoints..."
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        local endpoints
        endpoints=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null)
        for endpoint in $endpoints; do
            log_info "Deleting endpoint: $endpoint"
            aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$endpoint" 2>/dev/null || true
        done
        sleep 5
    fi

    echo ""
    log_step "Step 6/7: Deleting VPC..."
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        # Delete subnets
        local subnets
        subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text)
        for subnet in $subnets; do
            log_info "Deleting subnet: $subnet"
            aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
        done

        # Delete route tables
        local rts
        rts=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
        for rt in $rts; do
            log_info "Deleting route table: $rt"
            aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
        done

        # Delete security groups
        local sgs
        sgs=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
        for sg in $sgs; do
            log_info "Deleting security group: $sg"
            aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
        done

        # Detach and delete Internet Gateway
        local igw_ids
        igw_ids=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[].InternetGatewayId' --output text)
        for igw in $igw_ids; do
            log_info "Detaching and deleting Internet Gateway: $igw"
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id" 2>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id "$igw" 2>/dev/null || true
        done

        # Delete VPC
        aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || true
        log_info "Deleted VPC: $vpc_id"
    fi

    echo ""
    log_step "Step 7/7: Cleanup completed"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Destroy Completed${NC}"
    echo -e "${GREEN}========================================${NC}"
}

status() {
    local stack_name=$1

    log_info "Checking status..."
    echo ""

    if [ -n "$stack_name" ]; then
        echo -e "${BLUE}=== Stack: $stack_name ===${NC}"
        echo ""

        # VPC
        echo -e "${BLUE}VPC:${NC}"
        aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=$stack_name" \
            --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,State:State}' \
            --output table 2>/dev/null || echo "  No VPC found"

        # Get VPC ID for other queries
        local vpc_id
        vpc_id=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=$stack_name" \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

        if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
            echo ""
            echo -e "${BLUE}VPC Endpoints:${NC}"
            aws ec2 describe-vpc-endpoints \
                --filters "Name=vpc-id,Values=$vpc_id" \
                --query 'VpcEndpoints[].{EndpointId:VpcEndpointId,Service:ServiceName,Type:VpcEndpointType,State:State}' \
                --output table 2>/dev/null || echo "  No endpoints found"
        fi

        echo ""
        echo -e "${BLUE}EC2 Instances:${NC}"
        aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$stack_name-ec2" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress}' \
            --output table 2>/dev/null || echo "  No instances found"

        echo ""
        echo -e "${BLUE}S3 Buckets (matching stack name):${NC}"
        aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, '$stack_name')].{Name:Name,Created:CreationDate}" \
            --output table 2>/dev/null || echo "  No buckets found"

    else
        echo -e "${BLUE}=== All EC2 Instances ===${NC}"
        ec2_list

        echo ""
        echo -e "${BLUE}=== All VPCs ===${NC}"
        vpc_list

        echo ""
        echo -e "${BLUE}=== All VPC Endpoints ===${NC}"
        endpoint_list

        echo ""
        echo -e "${BLUE}=== All S3 Buckets ===${NC}"
        s3_list
    fi
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

    # VPC Endpoints
    endpoint-s3-create)
        endpoint_s3_create "$@"
        ;;
    endpoint-ssm-create)
        endpoint_ssm_create "$@"
        ;;
    endpoint-delete)
        endpoint_delete "$@"
        ;;
    endpoint-list)
        endpoint_list "$@"
        ;;

    # NAT Instance
    nat-create)
        nat_instance_create "$@"
        ;;
    nat-delete)
        nat_instance_delete "$@"
        ;;
    nat-list)
        nat_instance_list
        ;;
    nat-sg-create)
        nat_sg_create "$@"
        ;;

    # Security Groups
    sg-create)
        sg_create "$@"
        ;;
    sg-delete)
        sg_delete "$@"
        ;;

    # IAM
    role-create)
        role_create "$@"
        ;;
    role-delete)
        role_delete "$@"
        ;;

    # EC2
    ec2-create)
        ec2_create "$@"
        ;;
    ec2-delete)
        ec2_delete "$@"
        ;;
    ec2-list)
        ec2_list
        ;;
    ec2-connect)
        ec2_connect "$@"
        ;;

    # S3
    s3-create)
        s3_create "$@"
        ;;
    s3-delete)
        s3_delete "$@"
        ;;
    s3-list)
        s3_list
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
