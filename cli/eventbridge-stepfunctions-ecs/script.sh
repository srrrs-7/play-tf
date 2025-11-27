#!/bin/bash

set -e

# EventBridge → Step Functions → ECS Tasks Architecture Script
# Provides operations for event-driven container orchestration

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "EventBridge → Step Functions → ECS Tasks Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy event-driven ECS workflow stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "EventBridge:"
    echo "  bus-create <name>                          - Create event bus"
    echo "  bus-delete <name>                          - Delete event bus"
    echo "  bus-list                                   - List event buses"
    echo "  rule-create <bus> <name> <pattern>         - Create rule"
    echo "  rule-delete <bus> <name>                   - Delete rule"
    echo "  put-event <bus> <source> <type> <detail>   - Put event"
    echo ""
    echo "Step Functions:"
    echo "  sfn-create <name> <definition-file>        - Create state machine"
    echo "  sfn-delete <arn>                           - Delete state machine"
    echo "  sfn-list                                   - List state machines"
    echo "  sfn-start <arn> [input]                    - Start execution"
    echo "  sfn-executions <arn>                       - List executions"
    echo "  sfn-describe <execution-arn>               - Describe execution"
    echo ""
    echo "ECS:"
    echo "  cluster-create <name>                      - Create ECS cluster"
    echo "  cluster-delete <name>                      - Delete cluster"
    echo "  cluster-list                               - List clusters"
    echo "  task-def-create <name> <image>             - Create task definition"
    echo "  task-def-list                              - List task definitions"
    echo "  task-run <cluster> <task-def> [subnet]     - Run task"
    echo "  task-list <cluster>                        - List running tasks"
    echo ""
    exit 1
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_aws_cli() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured"
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

get_default_vpc() {
    aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text
}

get_default_subnets() {
    local vpc_id=$(get_default_vpc)
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text | tr '\t' ','
}

# EventBridge Functions
bus_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bus name required"; exit 1; }

    log_step "Creating event bus: $name"
    local arn=$(aws events create-event-bus --name "$name" --query 'EventBusArn' --output text)
    log_info "Event bus created: $arn"
}

bus_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bus name required"; exit 1; }
    aws events delete-event-bus --name "$name"
    log_info "Event bus deleted"
}

bus_list() {
    aws events list-event-buses --query 'EventBuses[].{Name:Name,Arn:Arn}' --output table
}

rule_create() {
    local bus=$1
    local name=$2
    local pattern=$3

    if [ -z "$bus" ] || [ -z "$name" ] || [ -z "$pattern" ]; then
        log_error "Bus name, rule name, and event pattern required"
        exit 1
    fi

    log_step "Creating rule: $name"
    aws events put-rule \
        --name "$name" \
        --event-bus-name "$bus" \
        --event-pattern "$pattern" \
        --state ENABLED

    log_info "Rule created"
}

rule_delete() {
    local bus=$1
    local name=$2

    # Remove targets first
    local targets=$(aws events list-targets-by-rule --event-bus-name "$bus" --rule "$name" --query 'Targets[].Id' --output text 2>/dev/null)
    if [ -n "$targets" ]; then
        aws events remove-targets --event-bus-name "$bus" --rule "$name" --ids $targets
    fi

    aws events delete-rule --event-bus-name "$bus" --name "$name"
    log_info "Rule deleted"
}

put_event() {
    local bus=$1
    local source=$2
    local detail_type=$3
    local detail=$4

    if [ -z "$bus" ] || [ -z "$source" ] || [ -z "$detail_type" ] || [ -z "$detail" ]; then
        log_error "Bus, source, detail-type, and detail required"
        exit 1
    fi

    aws events put-events --entries "[{
        \"EventBusName\": \"$bus\",
        \"Source\": \"$source\",
        \"DetailType\": \"$detail_type\",
        \"Detail\": \"$detail\"
    }]"
    log_info "Event sent"
}

# Step Functions
sfn_create() {
    local name=$1
    local definition_file=$2

    if [ -z "$name" ] || [ -z "$definition_file" ]; then
        log_error "Name and definition file required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-sfn-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    sleep 10

    local definition=$(cat "$definition_file")
    local arn=$(aws stepfunctions create-state-machine \
        --name "$name" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$role_name" \
        --query 'stateMachineArn' --output text)
    log_info "State Machine created: $arn"
}

sfn_delete() {
    local arn=$1
    [ -z "$arn" ] && { log_error "State machine ARN required"; exit 1; }
    aws stepfunctions delete-state-machine --state-machine-arn "$arn"
    log_info "State Machine deleted"
}

sfn_list() {
    aws stepfunctions list-state-machines --query 'stateMachines[].{Name:name,Arn:stateMachineArn}' --output table
}

sfn_start() {
    local arn=$1
    local input=${2:-"{}"}
    [ -z "$arn" ] && { log_error "State machine ARN required"; exit 1; }

    local execution_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$arn" \
        --input "$input" \
        --query 'executionArn' --output text)
    log_info "Execution started: $execution_arn"
}

sfn_executions() {
    local arn=$1
    [ -z "$arn" ] && { log_error "State machine ARN required"; exit 1; }
    aws stepfunctions list-executions --state-machine-arn "$arn" --query 'executions[].{Name:name,Status:status,StartDate:startDate}' --output table
}

sfn_describe() {
    local execution_arn=$1
    [ -z "$execution_arn" ] && { log_error "Execution ARN required"; exit 1; }
    aws stepfunctions describe-execution --execution-arn "$execution_arn" --output json
}

# ECS Functions
cluster_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Cluster name required"; exit 1; }

    log_step "Creating ECS cluster: $name"
    aws ecs create-cluster --cluster-name "$name" --capacity-providers FARGATE FARGATE_SPOT
    log_info "Cluster created"
}

cluster_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Cluster name required"; exit 1; }
    aws ecs delete-cluster --cluster "$name"
    log_info "Cluster deleted"
}

cluster_list() {
    aws ecs list-clusters --query 'clusterArns[]' --output table
}

task_def_create() {
    local name=$1
    local image=$2

    if [ -z "$name" ] || [ -z "$image" ]; then
        log_error "Task definition name and image required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-task-execution-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

    sleep 5

    local task_def=$(cat << EOF
{
    "family": "$name",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::$account_id:role/$role_name",
    "containerDefinitions": [{
        "name": "$name",
        "image": "$image",
        "essential": true,
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/$name",
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
    log_info "Task definition created: $name"
}

task_def_list() {
    aws ecs list-task-definitions --query 'taskDefinitionArns[]' --output table
}

task_run() {
    local cluster=$1
    local task_def=$2
    local subnet=$3

    if [ -z "$cluster" ] || [ -z "$task_def" ]; then
        log_error "Cluster and task definition required"
        exit 1
    fi

    if [ -z "$subnet" ]; then
        subnet=$(get_default_subnets | cut -d',' -f1)
    fi

    local vpc_id=$(aws ec2 describe-subnets --subnet-ids "$subnet" --query 'Subnets[0].VpcId' --output text)
    local sg=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text)

    aws ecs run-task \
        --cluster "$cluster" \
        --task-definition "$task_def" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$subnet],securityGroups=[$sg],assignPublicIp=ENABLED}"

    log_info "Task started"
}

task_list() {
    local cluster=$1
    [ -z "$cluster" ] && { log_error "Cluster name required"; exit 1; }
    aws ecs list-tasks --cluster "$cluster" --query 'taskArns[]' --output table
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying EventBridge → Step Functions → ECS Tasks stack: $name"
    local account_id=$(get_account_id)

    # Create ECS Cluster
    log_step "Creating ECS cluster..."
    aws ecs create-cluster --cluster-name "${name}-cluster" --capacity-providers FARGATE FARGATE_SPOT 2>/dev/null || log_info "Cluster already exists"

    # Create task execution role
    log_step "Creating task execution role..."
    local exec_role="${name}-task-exec-role"
    local exec_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$exec_role" --assume-role-policy-document "$exec_trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$exec_role" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

    # Create task role (for the actual task to use)
    local task_role="${name}-task-role"
    local task_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$task_role" --assume-role-policy-document "$task_trust" 2>/dev/null || true

    # Create task definition
    log_step "Creating task definition..."
    local task_def=$(cat << EOF
{
    "family": "${name}-task",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::$account_id:role/$exec_role",
    "taskRoleArn": "arn:aws:iam::$account_id:role/$task_role",
    "containerDefinitions": [{
        "name": "processor",
        "image": "amazon/amazon-ecs-sample",
        "essential": true,
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/${name}-task",
                "awslogs-region": "$DEFAULT_REGION",
                "awslogs-stream-prefix": "ecs",
                "awslogs-create-group": "true"
            }
        },
        "environment": [
            {"name": "TASK_NAME", "value": "${name}-task"}
        ]
    }]
}
EOF
)
    aws ecs register-task-definition --cli-input-json "$task_def" 2>/dev/null || true

    # Get networking info
    local subnets=$(get_default_subnets)
    local vpc_id=$(get_default_vpc)
    local sg=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text)

    # Create Step Functions state machine
    log_step "Creating Step Functions state machine..."
    local sfn_role="${name}-sfn-role"
    local sfn_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$sfn_role" --assume-role-policy-document "$sfn_trust" 2>/dev/null || true

    local sfn_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecs:RunTask",
                "ecs:StopTask",
                "ecs:DescribeTasks"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": [
                "arn:aws:iam::$account_id:role/$exec_role",
                "arn:aws:iam::$account_id:role/$task_role"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "events:PutTargets",
                "events:PutRule",
                "events:DescribeRule"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$sfn_role" --policy-name "${name}-sfn-policy" --policy-document "$sfn_policy"

    sleep 10

    local subnet_array=$(echo "$subnets" | tr ',' '\n' | head -2 | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')

    local sfn_definition=$(cat << EOF
{
    "Comment": "ECS Task orchestration workflow triggered by EventBridge",
    "StartAt": "ValidateInput",
    "States": {
        "ValidateInput": {
            "Type": "Pass",
            "Parameters": {
                "taskType.$": "$.taskType",
                "payload.$": "$.payload",
                "timestamp.$": "$$.State.EnteredTime"
            },
            "Next": "DetermineTaskType"
        },
        "DetermineTaskType": {
            "Type": "Choice",
            "Choices": [
                {
                    "Variable": "$.taskType",
                    "StringEquals": "batch",
                    "Next": "RunBatchTask"
                },
                {
                    "Variable": "$.taskType",
                    "StringEquals": "realtime",
                    "Next": "RunRealtimeTask"
                }
            ],
            "Default": "RunDefaultTask"
        },
        "RunBatchTask": {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.sync",
            "Parameters": {
                "LaunchType": "FARGATE",
                "Cluster": "arn:aws:ecs:$DEFAULT_REGION:$account_id:cluster/${name}-cluster",
                "TaskDefinition": "arn:aws:ecs:$DEFAULT_REGION:$account_id:task-definition/${name}-task",
                "NetworkConfiguration": {
                    "AwsvpcConfiguration": {
                        "Subnets": [$subnet_array],
                        "SecurityGroups": ["$sg"],
                        "AssignPublicIp": "ENABLED"
                    }
                },
                "Overrides": {
                    "ContainerOverrides": [{
                        "Name": "processor",
                        "Environment": [
                            {"Name": "TASK_TYPE", "Value": "batch"},
                            {"Name": "PAYLOAD", "Value.$": "States.JsonToString($.payload)"}
                        ]
                    }]
                }
            },
            "Next": "TaskCompleted",
            "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "TaskFailed"
            }]
        },
        "RunRealtimeTask": {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.sync",
            "Parameters": {
                "LaunchType": "FARGATE",
                "Cluster": "arn:aws:ecs:$DEFAULT_REGION:$account_id:cluster/${name}-cluster",
                "TaskDefinition": "arn:aws:ecs:$DEFAULT_REGION:$account_id:task-definition/${name}-task",
                "NetworkConfiguration": {
                    "AwsvpcConfiguration": {
                        "Subnets": [$subnet_array],
                        "SecurityGroups": ["$sg"],
                        "AssignPublicIp": "ENABLED"
                    }
                },
                "Overrides": {
                    "ContainerOverrides": [{
                        "Name": "processor",
                        "Environment": [
                            {"Name": "TASK_TYPE", "Value": "realtime"},
                            {"Name": "PAYLOAD", "Value.$": "States.JsonToString($.payload)"}
                        ]
                    }]
                }
            },
            "Next": "TaskCompleted",
            "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "TaskFailed"
            }]
        },
        "RunDefaultTask": {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.sync",
            "Parameters": {
                "LaunchType": "FARGATE",
                "Cluster": "arn:aws:ecs:$DEFAULT_REGION:$account_id:cluster/${name}-cluster",
                "TaskDefinition": "arn:aws:ecs:$DEFAULT_REGION:$account_id:task-definition/${name}-task",
                "NetworkConfiguration": {
                    "AwsvpcConfiguration": {
                        "Subnets": [$subnet_array],
                        "SecurityGroups": ["$sg"],
                        "AssignPublicIp": "ENABLED"
                    }
                }
            },
            "Next": "TaskCompleted",
            "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "TaskFailed"
            }]
        },
        "TaskCompleted": {
            "Type": "Pass",
            "Parameters": {
                "status": "COMPLETED",
                "message": "ECS task completed successfully"
            },
            "End": true
        },
        "TaskFailed": {
            "Type": "Fail",
            "Error": "ECSTaskFailed",
            "Cause": "ECS task execution failed"
        }
    }
}
EOF
)

    local sfn_arn=$(aws stepfunctions create-state-machine \
        --name "${name}-workflow" \
        --definition "$sfn_definition" \
        --role-arn "arn:aws:iam::$account_id:role/$sfn_role" \
        --query 'stateMachineArn' --output text 2>/dev/null || \
        aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:$DEFAULT_REGION:$account_id:stateMachine:${name}-workflow" --query 'stateMachineArn' --output text)

    # Create EventBridge event bus and rule
    log_step "Creating EventBridge resources..."
    aws events create-event-bus --name "${name}-bus" 2>/dev/null || true

    # Create role for EventBridge to start Step Functions
    local eb_role="${name}-eventbridge-role"
    local eb_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$eb_role" --assume-role-policy-document "$eb_trust" 2>/dev/null || true

    local eb_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["states:StartExecution"],
        "Resource": ["$sfn_arn"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$eb_role" --policy-name "${name}-sfn-start" --policy-document "$eb_policy"

    sleep 5

    # Create EventBridge rule
    local pattern='{"source": ["task.service"], "detail-type": ["TaskRequested"]}'
    aws events put-rule \
        --name "${name}-task-rule" \
        --event-bus-name "${name}-bus" \
        --event-pattern "$pattern" \
        --state ENABLED 2>/dev/null || true

    # Add Step Functions as target
    aws events put-targets \
        --event-bus-name "${name}-bus" \
        --rule "${name}-task-rule" \
        --targets "Id=sfn-target,Arn=$sfn_arn,RoleArn=arn:aws:iam::$account_id:role/$eb_role,InputPath=\$.detail"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Event Bus: ${name}-bus"
    echo "State Machine: $sfn_arn"
    echo "ECS Cluster: ${name}-cluster"
    echo "Task Definition: ${name}-task"
    echo ""
    echo "Test with:"
    echo "  aws events put-events --entries '[{"
    echo "    \"EventBusName\": \"${name}-bus\","
    echo "    \"Source\": \"task.service\","
    echo "    \"DetailType\": \"TaskRequested\","
    echo "    \"Detail\": \"{\\\"taskType\\\": \\\"batch\\\", \\\"payload\\\": {\\\"items\\\": [1,2,3]}}\""
    echo "  }]'"
    echo ""
    echo "Check execution:"
    echo "  aws stepfunctions list-executions --state-machine-arn '$sfn_arn'"
    echo ""
    echo "Check ECS tasks:"
    echo "  aws ecs list-tasks --cluster '${name}-cluster'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Remove EventBridge targets and rules
    aws events remove-targets --event-bus-name "${name}-bus" --rule "${name}-task-rule" --ids sfn-target 2>/dev/null || true
    aws events delete-rule --event-bus-name "${name}-bus" --name "${name}-task-rule" 2>/dev/null || true
    aws events delete-event-bus --name "${name}-bus" 2>/dev/null || true

    # Delete Step Functions
    local sfn_arn="arn:aws:states:${DEFAULT_REGION}:${account_id}:stateMachine:${name}-workflow"
    aws stepfunctions delete-state-machine --state-machine-arn "$sfn_arn" 2>/dev/null || true

    # Stop running tasks
    local tasks=$(aws ecs list-tasks --cluster "${name}-cluster" --query 'taskArns[]' --output text 2>/dev/null)
    for task in $tasks; do
        aws ecs stop-task --cluster "${name}-cluster" --task "$task" 2>/dev/null || true
    done

    # Deregister task definitions
    local task_defs=$(aws ecs list-task-definitions --family-prefix "${name}-task" --query 'taskDefinitionArns[]' --output text)
    for td in $task_defs; do
        aws ecs deregister-task-definition --task-definition "$td" 2>/dev/null || true
    done

    # Delete ECS cluster
    aws ecs delete-cluster --cluster "${name}-cluster" 2>/dev/null || true

    # Delete CloudWatch log group
    aws logs delete-log-group --log-group-name "/ecs/${name}-task" 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-sfn-role" --policy-name "${name}-sfn-policy" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-sfn-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-eventbridge-role" --policy-name "${name}-sfn-start" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-eventbridge-role" 2>/dev/null || true

    aws iam detach-role-policy --role-name "${name}-task-exec-role" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true
    aws iam delete-role --role-name "${name}-task-exec-role" 2>/dev/null || true

    aws iam delete-role --role-name "${name}-task-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Event Buses ===${NC}"
    bus_list
    echo -e "\n${BLUE}=== Step Functions ===${NC}"
    sfn_list
    echo -e "\n${BLUE}=== ECS Clusters ===${NC}"
    cluster_list
    echo -e "\n${BLUE}=== Task Definitions ===${NC}"
    task_def_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    bus-create) bus_create "$@" ;;
    bus-delete) bus_delete "$@" ;;
    bus-list) bus_list ;;
    rule-create) rule_create "$@" ;;
    rule-delete) rule_delete "$@" ;;
    put-event) put_event "$@" ;;
    sfn-create) sfn_create "$@" ;;
    sfn-delete) sfn_delete "$@" ;;
    sfn-list) sfn_list ;;
    sfn-start) sfn_start "$@" ;;
    sfn-executions) sfn_executions "$@" ;;
    sfn-describe) sfn_describe "$@" ;;
    cluster-create) cluster_create "$@" ;;
    cluster-delete) cluster_delete "$@" ;;
    cluster-list) cluster_list ;;
    task-def-create) task_def_create "$@" ;;
    task-def-list) task_def_list ;;
    task-run) task_run "$@" ;;
    task-list) task_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
