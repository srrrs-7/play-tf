#!/bin/bash

set -e

# CloudFront → ALB → EC2 (Auto Scaling) → RDS Architecture Script
# Provides operations for managing a classic 3-tier web architecture

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_INSTANCE_TYPE="t3.micro"
DEFAULT_RDS_INSTANCE_CLASS="db.t3.micro"
DEFAULT_MIN_SIZE=1
DEFAULT_MAX_SIZE=3
DEFAULT_DESIRED_CAPACITY=2

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → ALB → EC2 (Auto Scaling) → RDS Architecture"
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
    echo "  tg-create <name> <vpc-id> <port>     - Create Target Group"
    echo "  tg-delete <tg-arn>                   - Delete Target Group"
    echo ""
    echo "EC2 Auto Scaling Commands:"
    echo "  asg-create <name> <launch-tpl-id> <subnet-ids> <tg-arn> - Create Auto Scaling Group"
    echo "  asg-delete <name>                    - Delete Auto Scaling Group"
    echo "  asg-list                             - List Auto Scaling Groups"
    echo "  asg-update <name> <min> <max> <desired> - Update ASG capacity"
    echo "  lt-create <name> <ami-id> <instance-type> <key-name> <sg-id> - Create Launch Template"
    echo "  lt-delete <lt-id>                    - Delete Launch Template"
    echo "  lt-list                              - List Launch Templates"
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
    echo "  vpc-delete <vpc-id>                  - Delete VPC and associated resources"
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

    # Create and configure route table for public subnets
    local public_rt
    public_rt=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name-public-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route --route-table-id "$public_rt" --destination-cidr-block "0.0.0.0/0" --gateway-id "$igw_id"
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_1"
    aws ec2 associate-route-table --route-table-id "$public_rt" --subnet-id "$public_subnet_2"

    # Enable auto-assign public IP for public subnets
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_1" --map-public-ip-on-launch
    aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_2" --map-public-ip-on-launch

    log_info "Configured route tables"

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

    # Delete NAT Gateways
    local nat_gateways
    nat_gateways=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --query 'NatGateways[].NatGatewayId' --output text)
    for nat in $nat_gateways; do
        log_info "Deleting NAT Gateway: $nat"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat"
    done

    # Wait for NAT gateways to be deleted
    if [ -n "$nat_gateways" ]; then
        log_info "Waiting for NAT Gateways to be deleted..."
        sleep 30
    fi

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

    # Delete route tables (except main)
    local route_tables
    route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for rt in $route_tables; do
        log_info "Deleting route table: $rt"
        aws ec2 delete-route-table --route-table-id "$rt"
    done

    # Delete security groups (except default)
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

    # Allow HTTP and HTTPS
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

    # Get ALB DNS name
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

    # Delete listeners first
    local listeners
    listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$alb_arn" --query 'Listeners[].ListenerArn' --output text)
    for listener in $listeners; do
        log_info "Deleting listener: $listener"
        aws elbv2 delete-listener --listener-arn "$listener"
    done

    # Delete ALB
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn"
    log_info "ALB deleted successfully"
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

    log_step "Creating Target Group: $name"

    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$name" \
        --protocol HTTP \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --target-type instance \
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

# ============================================
# EC2 Auto Scaling Functions
# ============================================

lt_create() {
    local name=$1
    local ami_id=$2
    local instance_type=${3:-$DEFAULT_INSTANCE_TYPE}
    local key_name=$4
    local sg_id=$5

    if [ -z "$name" ] || [ -z "$ami_id" ]; then
        log_error "Launch template name and AMI ID are required"
        exit 1
    fi

    log_step "Creating Launch Template: $name"

    local user_data
    user_data=$(cat << 'USERDATA' | base64 -w 0
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
USERDATA
)

    local lt_args="--launch-template-name $name --version-description v1"

    local launch_template_data="{\"ImageId\":\"$ami_id\",\"InstanceType\":\"$instance_type\""

    if [ -n "$key_name" ]; then
        launch_template_data="$launch_template_data,\"KeyName\":\"$key_name\""
    fi

    if [ -n "$sg_id" ]; then
        launch_template_data="$launch_template_data,\"SecurityGroupIds\":[\"$sg_id\"]"
    fi

    launch_template_data="$launch_template_data,\"UserData\":\"$user_data\"}"

    local lt_id
    lt_id=$(aws ec2 create-launch-template \
        --launch-template-name "$name" \
        --version-description "v1" \
        --launch-template-data "$launch_template_data" \
        --query 'LaunchTemplate.LaunchTemplateId' --output text)

    log_info "Created Launch Template: $lt_id"
    echo "$lt_id"
}

lt_delete() {
    local lt_id=$1

    if [ -z "$lt_id" ]; then
        log_error "Launch Template ID is required"
        exit 1
    fi

    log_step "Deleting Launch Template: $lt_id"
    aws ec2 delete-launch-template --launch-template-id "$lt_id"
    log_info "Launch Template deleted"
}

lt_list() {
    log_info "Listing Launch Templates..."
    aws ec2 describe-launch-templates \
        --query 'LaunchTemplates[].{Name:LaunchTemplateName,ID:LaunchTemplateId,Version:LatestVersionNumber,Created:CreateTime}' \
        --output table
}

asg_create() {
    local name=$1
    local lt_id=$2
    local subnet_ids=$3  # comma-separated
    local tg_arn=$4

    if [ -z "$name" ] || [ -z "$lt_id" ] || [ -z "$subnet_ids" ]; then
        log_error "ASG name, Launch Template ID, and subnet IDs are required"
        exit 1
    fi

    log_step "Creating Auto Scaling Group: $name"

    local asg_args="--auto-scaling-group-name $name"
    asg_args="$asg_args --launch-template LaunchTemplateId=$lt_id,Version=\$Latest"
    asg_args="$asg_args --min-size $DEFAULT_MIN_SIZE"
    asg_args="$asg_args --max-size $DEFAULT_MAX_SIZE"
    asg_args="$asg_args --desired-capacity $DEFAULT_DESIRED_CAPACITY"
    asg_args="$asg_args --vpc-zone-identifier $subnet_ids"

    if [ -n "$tg_arn" ]; then
        asg_args="$asg_args --target-group-arns $tg_arn"
    fi

    asg_args="$asg_args --health-check-type ELB"
    asg_args="$asg_args --health-check-grace-period 300"

    aws autoscaling create-auto-scaling-group $asg_args

    log_info "Created Auto Scaling Group: $name"

    # Add scaling policies
    log_info "Adding scaling policies..."

    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "$name" \
        --policy-name "$name-scale-out" \
        --policy-type TargetTrackingScaling \
        --target-tracking-configuration '{
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ASGAverageCPUUtilization"
            },
            "TargetValue": 70.0
        }'

    log_info "Auto Scaling Group created with scaling policies"
}

asg_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "ASG name is required"
        exit 1
    fi

    log_warn "This will delete Auto Scaling Group: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting Auto Scaling Group: $name"

    # First, set desired capacity to 0
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$name" \
        --min-size 0 \
        --desired-capacity 0

    log_info "Waiting for instances to terminate..."
    sleep 60

    # Delete ASG
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name "$name" \
        --force-delete

    log_info "Auto Scaling Group deleted"
}

asg_list() {
    log_info "Listing Auto Scaling Groups..."
    aws autoscaling describe-auto-scaling-groups \
        --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,Instances:Instances[].InstanceId|length(@)}' \
        --output table
}

asg_update() {
    local name=$1
    local min=$2
    local max=$3
    local desired=$4

    if [ -z "$name" ]; then
        log_error "ASG name is required"
        exit 1
    fi

    log_step "Updating Auto Scaling Group: $name"

    local update_args="--auto-scaling-group-name $name"
    [ -n "$min" ] && update_args="$update_args --min-size $min"
    [ -n "$max" ] && update_args="$update_args --max-size $max"
    [ -n "$desired" ] && update_args="$update_args --desired-capacity $desired"

    aws autoscaling update-auto-scaling-group $update_args

    log_info "Auto Scaling Group updated"
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

    log_step "Deleting DB Subnet Group: $name"
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
    rds_args="$rds_args --multi-az"

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
        --query 'DBInstances[0].{Identifier:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine,EngineVersion:EngineVersion,Class:DBInstanceClass,Endpoint:Endpoint.Address,Port:Endpoint.Port,MultiAZ:MultiAZ}' \
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
    "Comment": "CloudFront distribution for $stack_name",
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

    # Get current config
    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)

    # Disable distribution
    local disabled_config
    disabled_config=$(echo "$config" | jq '.Enabled = false')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$disabled_config"

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    # Get new ETag and delete
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
    echo "  - VPC with public and private subnets"
    echo "  - Application Load Balancer"
    echo "  - EC2 Auto Scaling Group"
    echo "  - RDS MySQL instance"
    echo "  - CloudFront distribution"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Step 1/5: Creating VPC..."
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
    log_warn "Please ensure you have noted all resource IDs"
    echo ""
    echo "Recommended deletion order:"
    echo "  1. CloudFront distribution"
    echo "  2. Auto Scaling Group"
    echo "  3. Launch Template"
    echo "  4. ALB and Target Groups"
    echo "  5. RDS instance"
    echo "  6. DB Subnet Group"
    echo "  7. Security Groups"
    echo "  8. VPC"
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

    echo -e "\n${BLUE}=== Auto Scaling Groups ===${NC}"
    asg_list

    echo -e "\n${BLUE}=== RDS Instances ===${NC}"
    rds_list

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

    # EC2 Auto Scaling
    lt-create)
        lt_create "$@"
        ;;
    lt-delete)
        lt_delete "$@"
        ;;
    lt-list)
        lt_list
        ;;
    asg-create)
        asg_create "$@"
        ;;
    asg-delete)
        asg_delete "$@"
        ;;
    asg-list)
        asg_list
        ;;
    asg-update)
        asg_update "$@"
        ;;

    # RDS
    rds-create)
        rds_create "$@"
        ;;
    rds-delete)
        rds_delete "$@"
        ;;
    rds-list)
        rds_list
        ;;
    rds-status)
        rds_status "$@"
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
