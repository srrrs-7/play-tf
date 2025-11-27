#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# CloudFront → Elastic Beanstalk → RDS Architecture Script
# Provides operations for managing a PaaS-based architecture

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_INSTANCE_TYPE="t3.micro"
DEFAULT_RDS_INSTANCE_CLASS="db.t3.micro"

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → Elastic Beanstalk → RDS Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status <stack-name>                  - Show status of all components"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <eb-url> <stack-name>     - Create CloudFront distribution"
    echo "  cf-delete <distribution-id>          - Delete CloudFront distribution"
    echo "  cf-list                              - List CloudFront distributions"
    echo "  cf-invalidate <dist-id> <path>       - Invalidate CloudFront cache"
    echo ""
    echo "Elastic Beanstalk Commands:"
    echo "  eb-app-create <name>                 - Create EB application"
    echo "  eb-app-delete <name>                 - Delete EB application"
    echo "  eb-app-list                          - List EB applications"
    echo "  eb-env-create <app> <env-name> <platform> - Create EB environment"
    echo "  eb-env-delete <app> <env-name>       - Delete EB environment"
    echo "  eb-env-list <app>                    - List EB environments"
    echo "  eb-env-status <app> <env-name>       - Show environment status"
    echo "  eb-env-health <app> <env-name>       - Show environment health"
    echo "  eb-deploy <app> <env-name> <zip-file> - Deploy application version"
    echo "  eb-logs <app> <env-name>             - View environment logs"
    echo "  eb-config-set <app> <env-name> <key> <value> - Set environment variable"
    echo "  eb-config-list <app> <env-name>      - List environment variables"
    echo "  eb-scale <app> <env-name> <min> <max> - Configure auto scaling"
    echo "  eb-platforms                         - List available platforms"
    echo "  eb-rebuild <app> <env-name>          - Rebuild environment"
    echo "  eb-restart <app> <env-name>          - Restart app servers"
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

# Check AWS CLI is configured

# Get AWS Account ID

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
# Elastic Beanstalk Application Functions
# ============================================

eb_app_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Application name is required"
        exit 1
    fi

    log_step "Creating Elastic Beanstalk application: $name"

    aws elasticbeanstalk create-application \
        --application-name "$name" \
        --description "Elastic Beanstalk application for $name"

    log_info "Application created: $name"
}

eb_app_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Application name is required"
        exit 1
    fi

    log_warn "This will delete EB application: $name and all its environments"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting Elastic Beanstalk application: $name"
    aws elasticbeanstalk delete-application \
        --application-name "$name" \
        --terminate-env-by-force

    log_info "Application deletion initiated"
}

eb_app_list() {
    log_info "Listing Elastic Beanstalk applications..."
    aws elasticbeanstalk describe-applications \
        --query 'Applications[].{Name:ApplicationName,Created:DateCreated,Updated:DateUpdated}' \
        --output table
}

# ============================================
# Elastic Beanstalk Environment Functions
# ============================================

eb_env_create() {
    local app=$1
    local env_name=$2
    local platform=$3

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    # Default platform if not specified
    if [ -z "$platform" ]; then
        platform="64bit Amazon Linux 2023 v6.1.0 running Node.js 18"
        log_info "Using default platform: $platform"
    fi

    log_step "Creating Elastic Beanstalk environment: $env_name"

    # Get solution stack name
    local solution_stack
    solution_stack=$(aws elasticbeanstalk list-available-solution-stacks \
        --query "SolutionStacks[?contains(@, '$(echo $platform | cut -d' ' -f1-3)')]|[0]" \
        --output text 2>/dev/null || echo "$platform")

    aws elasticbeanstalk create-environment \
        --application-name "$app" \
        --environment-name "$env_name" \
        --solution-stack-name "$solution_stack" \
        --option-settings \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value="$DEFAULT_INSTANCE_TYPE" \
            Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=LoadBalanced \
            Namespace=aws:elasticbeanstalk:environment,OptionName=LoadBalancerType,Value=application

    log_info "Environment creation initiated. This may take several minutes..."
    log_info "Use 'eb-env-status $app $env_name' to check the status"
}

eb_env_delete() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_warn "This will terminate EB environment: $env_name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Terminating Elastic Beanstalk environment: $env_name"
    aws elasticbeanstalk terminate-environment \
        --environment-name "$env_name"

    log_info "Environment termination initiated"
}

eb_env_list() {
    local app=$1

    if [ -z "$app" ]; then
        log_info "Listing all Elastic Beanstalk environments..."
        aws elasticbeanstalk describe-environments \
            --query 'Environments[].{App:ApplicationName,Env:EnvironmentName,Status:Status,Health:Health,URL:CNAME}' \
            --output table
    else
        log_info "Listing environments for application: $app"
        aws elasticbeanstalk describe-environments \
            --application-name "$app" \
            --query 'Environments[].{Env:EnvironmentName,Status:Status,Health:Health,URL:CNAME}' \
            --output table
    fi
}

eb_env_status() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_info "Environment status: $env_name"
    aws elasticbeanstalk describe-environments \
        --application-name "$app" \
        --environment-names "$env_name" \
        --query 'Environments[0].{Name:EnvironmentName,Status:Status,Health:Health,HealthStatus:HealthStatus,URL:CNAME,Platform:SolutionStackName}' \
        --output table
}

eb_env_health() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_info "Environment health: $env_name"
    aws elasticbeanstalk describe-environment-health \
        --environment-name "$env_name" \
        --attribute-names All \
        --query '{Color:Color,Status:Status,Causes:Causes,InstancesHealth:InstancesHealth}'
}

eb_deploy() {
    local app=$1
    local env_name=$2
    local zip_file=$3

    if [ -z "$app" ] || [ -z "$env_name" ] || [ -z "$zip_file" ]; then
        log_error "Application name, environment name, and zip file are required"
        exit 1
    fi

    if [ ! -f "$zip_file" ]; then
        log_error "Zip file does not exist: $zip_file"
        exit 1
    fi

    local version_label="v-$(date +%Y%m%d-%H%M%S)"
    local s3_bucket="elasticbeanstalk-$DEFAULT_REGION-$(get_account_id)"
    local s3_key="$app/$version_label.zip"

    log_step "Deploying application to: $env_name"

    # Ensure S3 bucket exists
    aws s3 mb "s3://$s3_bucket" 2>/dev/null || true

    # Upload to S3
    log_info "Uploading application bundle to S3..."
    aws s3 cp "$zip_file" "s3://$s3_bucket/$s3_key"

    # Create application version
    log_info "Creating application version: $version_label"
    aws elasticbeanstalk create-application-version \
        --application-name "$app" \
        --version-label "$version_label" \
        --source-bundle S3Bucket="$s3_bucket",S3Key="$s3_key"

    # Deploy to environment
    log_info "Deploying to environment..."
    aws elasticbeanstalk update-environment \
        --application-name "$app" \
        --environment-name "$env_name" \
        --version-label "$version_label"

    log_info "Deployment initiated. Use 'eb-env-status $app $env_name' to check progress"
}

eb_logs() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_step "Requesting environment logs..."

    # Request logs
    aws elasticbeanstalk request-environment-info \
        --environment-name "$env_name" \
        --info-type tail

    log_info "Waiting for logs..."
    sleep 5

    # Retrieve logs
    aws elasticbeanstalk retrieve-environment-info \
        --environment-name "$env_name" \
        --info-type tail \
        --query 'EnvironmentInfo[].Message' \
        --output text
}

eb_config_set() {
    local app=$1
    local env_name=$2
    local key=$3
    local value=$4

    if [ -z "$app" ] || [ -z "$env_name" ] || [ -z "$key" ] || [ -z "$value" ]; then
        log_error "Application name, environment name, key, and value are required"
        exit 1
    fi

    log_step "Setting environment variable: $key"

    aws elasticbeanstalk update-environment \
        --application-name "$app" \
        --environment-name "$env_name" \
        --option-settings \
            Namespace=aws:elasticbeanstalk:application:environment,OptionName="$key",Value="$value"

    log_info "Environment variable set. Environment is updating..."
}

eb_config_list() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_info "Listing environment variables..."
    aws elasticbeanstalk describe-configuration-settings \
        --application-name "$app" \
        --environment-name "$env_name" \
        --query "ConfigurationSettings[0].OptionSettings[?Namespace=='aws:elasticbeanstalk:application:environment'].{Key:OptionName,Value:Value}" \
        --output table
}

eb_scale() {
    local app=$1
    local env_name=$2
    local min=${3:-1}
    local max=${4:-4}

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_step "Configuring auto scaling: min=$min, max=$max"

    aws elasticbeanstalk update-environment \
        --application-name "$app" \
        --environment-name "$env_name" \
        --option-settings \
            Namespace=aws:autoscaling:asg,OptionName=MinSize,Value="$min" \
            Namespace=aws:autoscaling:asg,OptionName=MaxSize,Value="$max"

    log_info "Auto scaling configuration updated"
}

eb_platforms() {
    log_info "Listing available Elastic Beanstalk platforms..."
    aws elasticbeanstalk list-available-solution-stacks \
        --query 'SolutionStacks[]' \
        --output table
}

eb_rebuild() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_warn "This will rebuild the environment: $env_name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Rebuilding environment: $env_name"
    aws elasticbeanstalk rebuild-environment \
        --environment-name "$env_name"

    log_info "Environment rebuild initiated"
}

eb_restart() {
    local app=$1
    local env_name=$2

    if [ -z "$app" ] || [ -z "$env_name" ]; then
        log_error "Application name and environment name are required"
        exit 1
    fi

    log_step "Restarting app servers in: $env_name"
    aws elasticbeanstalk restart-app-server \
        --environment-name "$env_name"

    log_info "App server restart initiated"
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
    local eb_url=$1
    local stack_name=$2

    if [ -z "$eb_url" ] || [ -z "$stack_name" ]; then
        log_error "Elastic Beanstalk URL and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution for Elastic Beanstalk"

    local dist_config=$(cat << EOF
{
    "CallerReference": "$stack_name-$(date +%s)",
    "Comment": "CloudFront for Elastic Beanstalk $stack_name",
    "DefaultCacheBehavior": {
        "TargetOriginId": "EB-$stack_name",
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
            "Id": "EB-$stack_name",
            "DomainName": "$eb_url",
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

    log_info "Deploying Elastic Beanstalk architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - VPC with public and private subnets"
    echo "  - Elastic Beanstalk application and environment"
    echo "  - RDS instance"
    echo "  - CloudFront distribution"
    echo ""
    echo "Prerequisites:"
    echo "  - aws-elasticbeanstalk-ec2-role IAM instance profile must exist"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Create VPC
    log_step "Step 1/4: Creating VPC..."
    vpc_create "$stack_name"

    # Create EB application
    log_step "Step 2/4: Creating Elastic Beanstalk application..."
    eb_app_create "$stack_name"

    log_info "Application created. Next steps:"
    echo ""
    echo "1. Create DB subnet group:"
    echo "   ./script.sh subnet-group-create $stack_name-db <private-subnet-1>,<private-subnet-2>"
    echo ""
    echo "2. Create RDS instance:"
    echo "   ./script.sh rds-create $stack_name-db mysql <username> <password> $stack_name-db"
    echo ""
    echo "3. Create EB environment:"
    echo "   ./script.sh eb-env-create $stack_name $stack_name-env"
    echo ""
    echo "4. Set database environment variables:"
    echo "   ./script.sh eb-config-set $stack_name $stack_name-env RDS_HOSTNAME <rds-endpoint>"
    echo "   ./script.sh eb-config-set $stack_name $stack_name-env RDS_PORT 3306"
    echo "   ./script.sh eb-config-set $stack_name $stack_name-env RDS_DB_NAME mydb"
    echo "   ./script.sh eb-config-set $stack_name $stack_name-env RDS_USERNAME <username>"
    echo "   ./script.sh eb-config-set $stack_name $stack_name-env RDS_PASSWORD <password>"
    echo ""
    echo "5. Deploy your application:"
    echo "   ./script.sh eb-deploy $stack_name $stack_name-env app.zip"
    echo ""
    echo "6. Create CloudFront distribution:"
    echo "   ./script.sh cf-create <eb-cname> $stack_name"
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
    echo "  2. Delete EB environment: eb-env-delete $stack_name $stack_name-env"
    echo "  3. Delete EB application: eb-app-delete $stack_name"
    echo "  4. Delete RDS instance: rds-delete $stack_name-db"
    echo "  5. Delete DB Subnet Group: subnet-group-delete $stack_name-db"
    echo "  6. Delete Security Groups"
    echo "  7. Delete VPC: vpc-delete <vpc-id>"
    echo ""

    log_info "Use individual delete commands with resource IDs"
}

status() {
    local stack_name=$1

    log_info "Checking status for: $stack_name"
    echo ""

    echo -e "${BLUE}=== Elastic Beanstalk Applications ===${NC}"
    eb_app_list

    echo -e "\n${BLUE}=== Elastic Beanstalk Environments ===${NC}"
    eb_env_list

    echo -e "\n${BLUE}=== RDS Instances ===${NC}"
    rds_list

    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list

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

    # Elastic Beanstalk Application
    eb-app-create) eb_app_create "$@" ;;
    eb-app-delete) eb_app_delete "$@" ;;
    eb-app-list) eb_app_list ;;

    # Elastic Beanstalk Environment
    eb-env-create) eb_env_create "$@" ;;
    eb-env-delete) eb_env_delete "$@" ;;
    eb-env-list) eb_env_list "$@" ;;
    eb-env-status) eb_env_status "$@" ;;
    eb-env-health) eb_env_health "$@" ;;
    eb-deploy) eb_deploy "$@" ;;
    eb-logs) eb_logs "$@" ;;
    eb-config-set) eb_config_set "$@" ;;
    eb-config-list) eb_config_list "$@" ;;
    eb-scale) eb_scale "$@" ;;
    eb-platforms) eb_platforms ;;
    eb-rebuild) eb_rebuild "$@" ;;
    eb-restart) eb_restart "$@" ;;

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
