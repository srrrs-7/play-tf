#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# API Gateway → VPC Link → ALB → ECS Architecture Script
# Provides operations for private API integration with ECS

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "API Gateway → VPC Link → ALB → ECS Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full architecture"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "VPC Link:"
    echo "  vpclink-create <name> <nlb-arn>      - Create VPC Link (for REST API)"
    echo "  vpclink-create-v2 <name> <subnet-ids> <sg-ids> - Create VPC Link (for HTTP API)"
    echo "  vpclink-delete <id>                  - Delete VPC Link"
    echo "  vpclink-list                         - List VPC Links"
    echo ""
    echo "API Gateway (HTTP API):"
    echo "  api-create <name>                    - Create HTTP API"
    echo "  api-delete <id>                      - Delete API"
    echo "  api-list                             - List APIs"
    echo "  api-integration <api-id> <vpclink-id> <alb-arn> - Create VPC Link integration"
    echo "  api-route <api-id> <method> <path> <integration-id> - Create route"
    echo "  api-deploy <api-id> <stage>          - Deploy API"
    echo ""
    echo "ALB (Internal):"
    echo "  alb-create <name> <vpc-id> <subnet-ids> - Create internal ALB"
    echo "  alb-delete <arn>                     - Delete ALB"
    echo "  alb-list                             - List ALBs"
    echo "  tg-create <name> <vpc-id> <port>     - Create target group (IP type)"
    echo "  listener-create <alb-arn> <tg-arn>   - Create listener"
    echo ""
    echo "ECS:"
    echo "  cluster-create <name>                - Create ECS cluster"
    echo "  cluster-delete <name>                - Delete cluster"
    echo "  service-create <cluster> <name> <task-def> <subnet-ids> <sg-id> <tg-arn> - Create service"
    echo "  service-delete <cluster> <name>      - Delete service"
    echo "  task-def-create <family> <image> <port> - Create task definition"
    echo ""
    echo "VPC:"
    echo "  vpc-create <name>                    - Create VPC"
    echo "  vpc-delete <vpc-id>                  - Delete VPC"
    echo ""
    exit 1
}

# VPC Link
vpclink_create() {
    local name=$1
    local nlb_arn=$2

    [ -z "$name" ] || [ -z "$nlb_arn" ] && {
        log_error "Name and NLB ARN required"
        exit 1
    }

    log_step "Creating VPC Link: $name"

    local vpclink_id
    vpclink_id=$(aws apigateway create-vpc-link \
        --name "$name" \
        --target-arns "$nlb_arn" \
        --query 'id' --output text)

    log_info "VPC Link created: $vpclink_id"
    log_info "Waiting for VPC Link to be available..."

    while true; do
        local status
        status=$(aws apigateway get-vpc-link --vpc-link-id "$vpclink_id" --query 'status' --output text)
        [ "$status" = "AVAILABLE" ] && break
        [ "$status" = "FAILED" ] && { log_error "VPC Link creation failed"; exit 1; }
        sleep 10
    done

    log_info "VPC Link available"
}

vpclink_create_v2() {
    local name=$1
    local subnet_ids=$2
    local sg_ids=$3

    [ -z "$name" ] || [ -z "$subnet_ids" ] && {
        log_error "Name and subnet IDs required"
        exit 1
    }

    log_step "Creating VPC Link (HTTP API): $name"

    local args="--name $name"
    args="$args --subnet-ids ${subnet_ids//,/ }"
    [ -n "$sg_ids" ] && args="$args --security-group-ids ${sg_ids//,/ }"

    local vpclink_id
    vpclink_id=$(aws apigatewayv2 create-vpc-link $args --query 'VpcLinkId' --output text)

    log_info "VPC Link created: $vpclink_id"
    echo "$vpclink_id"
}

vpclink_delete() {
    local id=$1
    aws apigatewayv2 delete-vpc-link --vpc-link-id "$id" 2>/dev/null || \
    aws apigateway delete-vpc-link --vpc-link-id "$id"
    log_info "VPC Link deleted"
}

vpclink_list() {
    log_info "VPC Links (HTTP API v2):"
    aws apigatewayv2 get-vpc-links --query 'Items[].{Id:VpcLinkId,Name:Name,Status:VpcLinkStatus}' --output table 2>/dev/null || true

    log_info "VPC Links (REST API v1):"
    aws apigateway get-vpc-links --query 'items[].{Id:id,Name:name,Status:status}' --output table 2>/dev/null || true
}

# API Gateway HTTP API
api_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Name required"; exit 1; }

    log_step "Creating HTTP API: $name"

    local api_id
    api_id=$(aws apigatewayv2 create-api \
        --name "$name" \
        --protocol-type HTTP \
        --query 'ApiId' --output text)

    log_info "API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local id=$1
    aws apigatewayv2 delete-api --api-id "$id"
    log_info "API deleted"
}

api_list() {
    aws apigatewayv2 get-apis --query 'Items[].{Name:Name,Id:ApiId,Endpoint:ApiEndpoint}' --output table
}

api_integration() {
    local api_id=$1
    local vpclink_id=$2
    local alb_arn=$3

    [ -z "$api_id" ] || [ -z "$vpclink_id" ] || [ -z "$alb_arn" ] && {
        log_error "API ID, VPC Link ID, and ALB ARN required"
        exit 1
    }

    log_step "Creating VPC Link integration"

    # Get ALB listener ARN
    local listener_arn
    listener_arn=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --query 'Listeners[0].ListenerArn' --output text)

    local integration_id
    integration_id=$(aws apigatewayv2 create-integration \
        --api-id "$api_id" \
        --integration-type HTTP_PROXY \
        --integration-method ANY \
        --integration-uri "$listener_arn" \
        --connection-type VPC_LINK \
        --connection-id "$vpclink_id" \
        --payload-format-version "1.0" \
        --query 'IntegrationId' --output text)

    log_info "Integration created: $integration_id"
    echo "$integration_id"
}

api_route() {
    local api_id=$1
    local method=$2
    local path=$3
    local integration_id=$4

    [ -z "$api_id" ] || [ -z "$method" ] || [ -z "$path" ] || [ -z "$integration_id" ] && {
        log_error "API ID, method, path, and integration ID required"
        exit 1
    }

    log_step "Creating route: $method $path"

    aws apigatewayv2 create-route \
        --api-id "$api_id" \
        --route-key "$method $path" \
        --target "integrations/$integration_id"

    log_info "Route created"
}

api_deploy() {
    local api_id=$1
    local stage=${2:-prod}

    [ -z "$api_id" ] && { log_error "API ID required"; exit 1; }

    log_step "Deploying to stage: $stage"

    aws apigatewayv2 create-stage \
        --api-id "$api_id" \
        --stage-name "$stage" \
        --auto-deploy 2>/dev/null || true

    local endpoint
    endpoint=$(aws apigatewayv2 get-api --api-id "$api_id" --query 'ApiEndpoint' --output text)

    log_info "Deployed: $endpoint/$stage"
}

# ALB (Internal)
alb_create() {
    local name=$1
    local vpc_id=$2
    local subnet_ids=$3

    [ -z "$name" ] || [ -z "$vpc_id" ] || [ -z "$subnet_ids" ] && {
        log_error "Name, VPC ID, and subnet IDs required"
        exit 1
    }

    log_step "Creating internal ALB: $name"

    # Create security group
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$name-alb-sg" \
        --description "SG for internal ALB" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 80 --cidr 10.0.0.0/8

    # Create ALB
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "$name" \
        --subnets ${subnet_ids//,/ } \
        --security-groups "$sg_id" \
        --scheme internal \
        --type application \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)

    log_info "Internal ALB created: $alb_arn"
    echo "$alb_arn"
}

alb_delete() {
    local arn=$1
    log_warn "Deleting ALB"

    local listeners
    listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$arn" --query 'Listeners[].ListenerArn' --output text)
    for l in $listeners; do
        aws elbv2 delete-listener --listener-arn "$l"
    done

    aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
    log_info "ALB deleted"
}

alb_list() {
    aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[].{Name:LoadBalancerName,Scheme:Scheme,DNSName:DNSName,ARN:LoadBalancerArn}' \
        --output table
}

tg_create() {
    local name=$1
    local vpc_id=$2
    local port=${3:-80}

    [ -z "$name" ] || [ -z "$vpc_id" ] && {
        log_error "Name and VPC ID required"
        exit 1
    }

    log_step "Creating target group: $name"

    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$name" \
        --protocol HTTP \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --target-type ip \
        --health-check-path "/" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)

    log_info "Target group created: $tg_arn"
    echo "$tg_arn"
}

listener_create() {
    local alb_arn=$1
    local tg_arn=$2

    [ -z "$alb_arn" ] || [ -z "$tg_arn" ] && {
        log_error "ALB ARN and target group ARN required"
        exit 1
    }

    aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$tg_arn"

    log_info "Listener created"
}

# ECS
cluster_create() {
    local name=$1
    aws ecs create-cluster --cluster-name "$name" --capacity-providers FARGATE
    log_info "Cluster created"
}

cluster_delete() {
    local name=$1
    aws ecs delete-cluster --cluster "$name"
    log_info "Cluster deleted"
}

task_def_create() {
    local family=$1
    local image=$2
    local port=${3:-80}

    [ -z "$family" ] || [ -z "$image" ] && {
        log_error "Family and image required"
        exit 1
    }

    log_step "Creating task definition: $family"

    local account_id=$(get_account_id)
    local execution_role="arn:aws:iam::$account_id:role/ecsTaskExecutionRole"

    local task_def=$(cat << EOF
{
    "family": "$family",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "$execution_role",
    "containerDefinitions": [{
        "name": "$family",
        "image": "$image",
        "essential": true,
        "portMappings": [{"containerPort": $port, "protocol": "tcp"}],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/$family",
                "awslogs-region": "$DEFAULT_REGION",
                "awslogs-stream-prefix": "ecs",
                "awslogs-create-group": "true"
            }
        }
    }]
}
EOF
)

    aws ecs register-task-definition --cli-input-json "$task_def"
    log_info "Task definition created"
}

service_create() {
    local cluster=$1
    local name=$2
    local task_def=$3
    local subnet_ids=$4
    local sg_id=$5
    local tg_arn=$6

    [ -z "$cluster" ] || [ -z "$name" ] || [ -z "$task_def" ] || [ -z "$subnet_ids" ] || [ -z "$sg_id" ] && {
        log_error "Cluster, name, task def, subnets, and SG required"
        exit 1
    }

    log_step "Creating ECS service: $name"

    local subnets_json=$(echo "$subnet_ids" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd,)
    local network="{\"awsvpcConfiguration\":{\"subnets\":[$subnets_json],\"securityGroups\":[\"$sg_id\"],\"assignPublicIp\":\"DISABLED\"}}"

    local args="--cluster $cluster --service-name $name --task-definition $task_def"
    args="$args --desired-count 2 --launch-type FARGATE --network-configuration $network"

    if [ -n "$tg_arn" ]; then
        local container=$(aws ecs describe-task-definition --task-definition "$task_def" --query 'taskDefinition.containerDefinitions[0].name' --output text)
        local port=$(aws ecs describe-task-definition --task-definition "$task_def" --query 'taskDefinition.containerDefinitions[0].portMappings[0].containerPort' --output text)
        args="$args --load-balancers targetGroupArn=$tg_arn,containerName=$container,containerPort=$port"
    fi

    aws ecs create-service $args
    log_info "Service created"
}

service_delete() {
    local cluster=$1
    local name=$2

    aws ecs update-service --cluster "$cluster" --service "$name" --desired-count 0
    sleep 30
    aws ecs delete-service --cluster "$cluster" --service "$name" --force
    log_info "Service deleted"
}

# VPC
vpc_create() {
    local name=$1
    log_step "Creating VPC: $name"

    local vpc_id=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name}]" --query 'Vpc.VpcId' --output text)
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames

    local azs=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text)
    local az_arr=($azs)

    local priv1=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "10.0.1.0/24" --availability-zone "${az_arr[0]}" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-1}]" --query 'Subnet.SubnetId' --output text)
    local priv2=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "10.0.2.0/24" --availability-zone "${az_arr[1]}" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name-private-2}]" --query 'Subnet.SubnetId' --output text)

    echo "VPC: $vpc_id"
    echo "Private Subnets: $priv1, $priv2"
}

vpc_delete() {
    local vpc_id=$1

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
    echo "This architecture connects API Gateway to private ECS services"
    echo "via VPC Link and internal ALB."
    echo ""
    echo "Manual steps required after VPC creation."
    echo ""

    read -p "Continue? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    vpc_create "$name"

    echo ""
    echo "Next steps:"
    echo "1. Create ECS cluster: cluster-create $name"
    echo "2. Create target group: tg-create $name-tg <vpc-id> 80"
    echo "3. Create internal ALB: alb-create $name-alb <vpc-id> <subnet-ids>"
    echo "4. Create listener: listener-create <alb-arn> <tg-arn>"
    echo "5. Create task definition: task-def-create $name <image> 80"
    echo "6. Create service: service-create $name $name-svc $name <subnet-ids> <sg-id> <tg-arn>"
    echo "7. Create VPC Link: vpclink-create-v2 $name-link <subnet-ids> <sg-ids>"
    echo "8. Create HTTP API: api-create $name"
    echo "9. Create integration: api-integration <api-id> <vpclink-id> <alb-arn>"
    echo "10. Create route: api-route <api-id> ANY /{proxy+} <integration-id>"
    echo "11. Deploy: api-deploy <api-id> prod"
}

destroy() {
    local name=$1
    log_warn "Destruction order:"
    echo "  1. API Gateway"
    echo "  2. VPC Link"
    echo "  3. ECS Service"
    echo "  4. ECS Cluster"
    echo "  5. ALB + Listeners"
    echo "  6. Target Group"
    echo "  7. Task Definition"
    echo "  8. VPC"
}

status() {
    echo -e "${BLUE}=== VPC Links ===${NC}"
    vpclink_list
    echo -e "\n${BLUE}=== HTTP APIs ===${NC}"
    api_list
    echo -e "\n${BLUE}=== ALBs ===${NC}"
    alb_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    vpclink-create) vpclink_create "$@" ;;
    vpclink-create-v2) vpclink_create_v2 "$@" ;;
    vpclink-delete) vpclink_delete "$@" ;;
    vpclink-list) vpclink_list ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-integration) api_integration "$@" ;;
    api-route) api_route "$@" ;;
    api-deploy) api_deploy "$@" ;;
    alb-create) alb_create "$@" ;;
    alb-delete) alb_delete "$@" ;;
    alb-list) alb_list ;;
    tg-create) tg_create "$@" ;;
    listener-create) listener_create "$@" ;;
    cluster-create) cluster_create "$@" ;;
    cluster-delete) cluster_delete "$@" ;;
    task-def-create) task_def_create "$@" ;;
    service-create) service_create "$@" ;;
    service-delete) service_delete "$@" ;;
    vpc-create) vpc_create "$@" ;;
    vpc-delete) vpc_delete "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
