#!/bin/bash
# =============================================================================
# ECS Job (run-task) Architecture Script
# =============================================================================
# This script creates and manages the following architecture:
#   - ECR repository for container images
#   - ECS Fargate cluster for running tasks
#   - ECS Task Definition
#   - CloudWatch Logs for logging
#   - IAM roles for task execution
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
DEFAULT_FARGATE_CPU="256"
DEFAULT_FARGATE_MEMORY="512"

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "ECS Job (run-task) Architecture"
    echo ""
    echo "  ECR -> ECS Fargate (run-task) -> CloudWatch Logs"
    echo ""
    echo "Commands:"
    echo ""
    echo "  === Full Stack ==="
    echo "  deploy <stack-name>                    - Deploy the full architecture"
    echo "  destroy <stack-name>                   - Destroy the full architecture"
    echo "  status [stack-name]                    - Show status of all components"
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
    echo "  task-create <family> <image> [cpu] [memory] [command]"
    echo "                                         - Create task definition"
    echo "  task-list                              - List task definitions"
    echo "  task-show <family>                     - Show task definition details"
    echo "  task-delete <family>                   - Deregister all revisions"
    echo ""
    echo "  === Job Execution ==="
    echo "  job-run <cluster> <task-def> [name]    - Run a job (ECS run-task)"
    echo "  job-run-wait <cluster> <task-def> [name]"
    echo "                                         - Run a job and wait for completion"
    echo "  job-list <cluster>                     - List running tasks"
    echo "  job-describe <cluster> <task-id>       - Describe task"
    echo "  job-stop <cluster> <task-id>           - Stop a running task"
    echo "  job-logs <task-def> <task-id>          - View task logs"
    echo ""
    echo "  === IAM ==="
    echo "  iam-create-role <name>                 - Create ECS task execution role"
    echo "  iam-delete-role <name>                 - Delete ECS task execution role"
    echo ""
    echo "  === CloudWatch Logs ==="
    echo "  logs-list                              - List ECS log groups"
    echo "  logs-tail <log-group>                  - Tail log group"
    echo "  logs-delete <log-group>                - Delete log group"
    echo ""
    echo "Examples:"
    echo "  # Deploy full stack"
    echo "  $0 deploy my-job"
    echo ""
    echo "  # Push container image and run job"
    echo "  $0 ecr-login"
    echo "  docker build -t my-job:latest ."
    echo "  $0 ecr-push my-job my-job:latest"
    echo "  $0 job-run my-job my-job"
    echo ""
    echo "  # Run job with custom command"
    echo "  $0 task-create my-job <image> 256 512 'echo hello world'"
    echo "  $0 job-run-wait my-job my-job"
    echo ""
    exit 1
}

# =============================================================================
# Helper Functions
# =============================================================================
get_default_vpc() {
    aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text
}

get_default_subnets() {
    local vpc_id=$(get_default_vpc)
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text | tr '\t' ' '
}

get_default_security_group() {
    local vpc_id=$(get_default_vpc)
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text
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
        --query 'clusters[*].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,PendingTasks:pendingTasksCount}' \
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
    local cpu=${3:-$DEFAULT_FARGATE_CPU}
    local memory=${4:-$DEFAULT_FARGATE_MEMORY}
    local command=$5

    require_param "$family" "Task family name"
    require_param "$image" "Container image"

    log_step "Creating task definition: $family"

    local account_id=$(get_account_id)
    local region=$(get_region)
    local execution_role_arn="arn:aws:iam::$account_id:role/${family}-task-execution-role"

    # Check if role exists, create if not
    if ! aws iam get-role --role-name "${family}-task-execution-role" &>/dev/null; then
        log_info "Creating task execution role..."
        iam_create_role "${family}-task-execution-role"
    fi

    # Build command array if provided
    local command_json=""
    if [ -n "$command" ]; then
        # Convert command string to JSON array
        command_json="\"command\": [\"sh\", \"-c\", \"$command\"],"
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
            $command_json
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
        --query 'taskDefinition.{Family:family,Revision:revision,Status:status,CPU:cpu,Memory:memory,Image:containerDefinitions[0].image}' \
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
# Job Execution Functions (run-task)
# =============================================================================
job_run() {
    local cluster=$1
    local task_def=$2
    local name=${3:-"job-$(date +%Y%m%d-%H%M%S)"}

    require_param "$cluster" "Cluster name"
    require_param "$task_def" "Task definition"

    log_step "Running job: $name"

    local subnets=$(get_default_subnets)
    local sg=$(get_default_security_group)
    local subnet_array=$(echo "$subnets" | tr ' ' '\n' | head -2 | tr '\n' ',' | sed 's/,$//')

    local task_arn
    task_arn=$(aws ecs run-task \
        --cluster "$cluster" \
        --task-definition "$task_def" \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={subnets=[$subnet_array],securityGroups=[$sg],assignPublicIp=ENABLED}" \
        --started-by "$name" \
        --query 'tasks[0].taskArn' --output text)

    local task_id=$(echo "$task_arn" | rev | cut -d'/' -f1 | rev)

    log_success "Job started"
    echo ""
    echo "Task ARN: $task_arn"
    echo "Task ID:  $task_id"
    echo ""
    echo "Check status:"
    echo "  $0 job-describe $cluster $task_id"
    echo ""
    echo "View logs:"
    echo "  $0 job-logs $task_def $task_id"
}

job_run_wait() {
    local cluster=$1
    local task_def=$2
    local name=${3:-"job-$(date +%Y%m%d-%H%M%S)"}

    require_param "$cluster" "Cluster name"
    require_param "$task_def" "Task definition"

    log_step "Running job and waiting for completion: $name"

    local subnets=$(get_default_subnets)
    local sg=$(get_default_security_group)
    local subnet_array=$(echo "$subnets" | tr ' ' '\n' | head -2 | tr '\n' ',' | sed 's/,$//')

    local task_arn
    task_arn=$(aws ecs run-task \
        --cluster "$cluster" \
        --task-definition "$task_def" \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={subnets=[$subnet_array],securityGroups=[$sg],assignPublicIp=ENABLED}" \
        --started-by "$name" \
        --query 'tasks[0].taskArn' --output text)

    local task_id=$(echo "$task_arn" | rev | cut -d'/' -f1 | rev)
    log_info "Task started: $task_id"
    log_info "Waiting for completion..."

    # Wait for task to complete
    aws ecs wait tasks-stopped --cluster "$cluster" --tasks "$task_arn"

    # Get exit code
    local exit_code
    exit_code=$(aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_arn" \
        --query 'tasks[0].containers[0].exitCode' --output text)

    local stop_reason
    stop_reason=$(aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_arn" \
        --query 'tasks[0].stoppedReason' --output text)

    echo ""
    echo -e "${BLUE}=== Job Result ===${NC}"
    echo "Task ID:     $task_id"
    echo "Exit Code:   $exit_code"
    echo "Stop Reason: $stop_reason"

    if [ "$exit_code" == "0" ]; then
        log_success "Job completed successfully"
    else
        log_error "Job failed with exit code: $exit_code"
    fi

    echo ""
    echo "View logs:"
    echo "  $0 job-logs $task_def $task_id"

    return ${exit_code:-1}
}

job_list() {
    local cluster=$1
    require_param "$cluster" "Cluster name"

    log_step "Listing tasks in cluster: $cluster"

    echo -e "\n${BLUE}=== Running Tasks ===${NC}"
    local running=$(aws ecs list-tasks --cluster "$cluster" --desired-status RUNNING --query 'taskArns' --output text)
    if [ -n "$running" ] && [ "$running" != "None" ]; then
        aws ecs describe-tasks \
            --cluster "$cluster" \
            --tasks $running \
            --query 'tasks[*].{TaskId:taskArn,Status:lastStatus,StartedAt:startedAt,TaskDef:taskDefinitionArn}' \
            --output table
    else
        echo "No running tasks"
    fi

    echo -e "\n${BLUE}=== Stopped Tasks (recent) ===${NC}"
    local stopped=$(aws ecs list-tasks --cluster "$cluster" --desired-status STOPPED --query 'taskArns' --output text)
    if [ -n "$stopped" ] && [ "$stopped" != "None" ]; then
        aws ecs describe-tasks \
            --cluster "$cluster" \
            --tasks $stopped \
            --query 'tasks[*].{TaskId:taskArn,Status:lastStatus,ExitCode:containers[0].exitCode,StoppedAt:stoppedAt}' \
            --output table
    else
        echo "No stopped tasks"
    fi
}

job_describe() {
    local cluster=$1
    local task_id=$2

    require_param "$cluster" "Cluster name"
    require_param "$task_id" "Task ID"

    log_step "Describing task: $task_id"

    aws ecs describe-tasks \
        --cluster "$cluster" \
        --tasks "$task_id" \
        --query 'tasks[0].{TaskArn:taskArn,Status:lastStatus,DesiredStatus:desiredStatus,StartedAt:startedAt,StoppedAt:stoppedAt,StoppedReason:stoppedReason,ExitCode:containers[0].exitCode,TaskDefinition:taskDefinitionArn}' \
        --output yaml
}

job_stop() {
    local cluster=$1
    local task_id=$2

    require_param "$cluster" "Cluster name"
    require_param "$task_id" "Task ID"

    log_step "Stopping task: $task_id"

    aws ecs stop-task \
        --cluster "$cluster" \
        --task "$task_id" \
        --reason "Stopped by user"

    log_success "Task stop initiated"
}

job_logs() {
    local task_def=$1
    local task_id=$2

    require_param "$task_def" "Task definition name"
    require_param "$task_id" "Task ID"

    local log_group="/ecs/$task_def"
    local log_stream="ecs/$task_def/$task_id"

    log_step "Fetching logs from: $log_group / $log_stream"

    aws logs get-log-events \
        --log-group-name "$log_group" \
        --log-stream-name "$log_stream" \
        --query 'events[*].message' \
        --output text 2>/dev/null || log_warn "No logs found (task may still be starting)"
}

# =============================================================================
# IAM Functions
# =============================================================================
iam_create_role() {
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

iam_delete_role() {
    local role_name=${1:-ecsTaskExecutionRole}

    confirm_action "This will delete IAM role '$role_name'"

    log_step "Deleting ECS task execution role: $role_name"
    delete_role_with_policies "$role_name"
    log_success "Deleted role: $role_name"
}

# =============================================================================
# CloudWatch Logs Functions
# =============================================================================
logs_list() {
    log_step "Listing ECS log groups..."
    aws logs describe-log-groups \
        --log-group-name-prefix "/ecs/" \
        --query 'logGroups[*].{Name:logGroupName,StoredBytes:storedBytes,RetentionDays:retentionInDays}' \
        --output table
}

logs_tail() {
    local log_group=$1
    require_param "$log_group" "Log group name"

    log_step "Tailing log group: $log_group"
    aws logs tail "$log_group" --follow
}

logs_delete() {
    local log_group=$1
    require_param "$log_group" "Log group name"

    confirm_action "This will delete log group '$log_group'"

    log_step "Deleting log group: $log_group"
    aws logs delete-log-group --log-group-name "$log_group"
    log_success "Deleted log group: $log_group"
}

# =============================================================================
# Full Stack Orchestration
# =============================================================================
deploy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_info "Deploying ECS Job architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - ECR repository for container images"
    echo "  - ECS Fargate cluster for job execution"
    echo "  - ECS Task Execution IAM Role"
    echo "  - CloudWatch Log Group"
    echo ""
    echo -e "${YELLOW}Note: You'll need to push a container image to ECR before running jobs${NC}"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    local account_id=$(get_account_id)
    local region=$(get_region)

    log_step "Step 1/4: Creating IAM role..."
    iam_create_role "${stack_name}-task-execution-role"
    sleep 5

    log_step "Step 2/4: Creating ECR repository..."
    aws ecr create-repository \
        --repository-name "$stack_name" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --query 'repository.repositoryUri' --output text 2>/dev/null || log_info "ECR repository already exists"
    local repo_uri="$account_id.dkr.ecr.$region.amazonaws.com/$stack_name"
    log_info "ECR Repository: $repo_uri"
    echo ""

    log_step "Step 3/4: Creating ECS cluster..."
    aws ecs create-cluster \
        --cluster-name "$stack_name" \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --settings name=containerInsights,value=enabled > /dev/null 2>/dev/null || log_info "ECS cluster already exists"
    log_info "ECS Cluster: $stack_name"
    echo ""

    log_step "Step 4/4: Creating CloudWatch Log Group..."
    aws logs create-log-group --log-group-name "/ecs/$stack_name" 2>/dev/null || log_info "Log group already exists"
    aws logs put-retention-policy --log-group-name "/ecs/$stack_name" --retention-in-days 30 2>/dev/null || true
    log_info "Log Group: /ecs/$stack_name"
    echo ""

    # Create a sample task definition using amazon/aws-cli as a test image
    log_step "Creating sample task definition..."
    local task_def=$(cat << EOF
{
    "family": "$stack_name",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::$account_id:role/${stack_name}-task-execution-role",
    "containerDefinitions": [
        {
            "name": "$stack_name",
            "image": "amazon/aws-cli:latest",
            "essential": true,
            "command": ["sts", "get-caller-identity"],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/$stack_name",
                    "awslogs-region": "$region",
                    "awslogs-stream-prefix": "ecs"
                }
            }
        }
    ]
}
EOF
)
    aws ecs register-task-definition --cli-input-json "$task_def" > /dev/null
    log_info "Task Definition: $stack_name"
    echo ""

    log_success "Deployment complete!"
    echo ""
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo "Stack Name:       $stack_name"
    echo "ECR Repository:   $repo_uri"
    echo "ECS Cluster:      $stack_name"
    echo "Task Definition:  $stack_name"
    echo "Log Group:        /ecs/$stack_name"
    echo ""
    echo -e "${YELLOW}=== Quick Start ===${NC}"
    echo ""
    echo "1. Test with sample job (uses aws-cli image):"
    echo "   $0 job-run $stack_name $stack_name test-job"
    echo ""
    echo "2. Or build and push your own container:"
    echo "   $0 ecr-login"
    echo "   docker build -t $stack_name:latest ."
    echo "   docker tag $stack_name:latest $repo_uri:latest"
    echo "   docker push $repo_uri:latest"
    echo ""
    echo "3. Update task definition to use your image:"
    echo "   $0 task-create $stack_name $repo_uri:latest 256 512 'your-command'"
    echo ""
    echo "4. Run your job:"
    echo "   $0 job-run-wait $stack_name $stack_name my-job"
    echo ""
    echo "5. View logs:"
    echo "   $0 logs-tail /ecs/$stack_name"
}

destroy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_warn "This will destroy all resources for: $stack_name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - ECS tasks (stopped)"
    echo "  - ECS cluster"
    echo "  - Task definitions"
    echo "  - ECR repository (and all images)"
    echo "  - CloudWatch log groups"
    echo "  - IAM role"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""

    # Stop running tasks
    log_step "Stopping running tasks..."
    local running=$(aws ecs list-tasks --cluster "$stack_name" --desired-status RUNNING --query 'taskArns' --output text 2>/dev/null)
    if [ -n "$running" ] && [ "$running" != "None" ]; then
        for task in $running; do
            aws ecs stop-task --cluster "$stack_name" --task "$task" --reason "Stack deletion" > /dev/null 2>&1 || true
            log_info "Stopped task: $task"
        done
    fi

    # Deregister task definitions
    log_step "Deregistering task definitions..."
    local task_arns=$(aws ecs list-task-definitions --family-prefix "$stack_name" --query 'taskDefinitionArns' --output text 2>/dev/null)
    for task_arn in $task_arns; do
        aws ecs deregister-task-definition --task-definition "$task_arn" > /dev/null 2>&1 || true
        log_info "Deregistered: $task_arn"
    done

    # Delete ECS cluster
    log_step "Deleting ECS cluster..."
    aws ecs delete-cluster --cluster "$stack_name" > /dev/null 2>&1 || true
    log_info "Deleted cluster: $stack_name"

    # Delete ECR repository
    log_step "Deleting ECR repository..."
    aws ecr delete-repository --repository-name "$stack_name" --force > /dev/null 2>&1 || true
    log_info "Deleted ECR repository: $stack_name"

    # Delete CloudWatch log groups
    log_step "Deleting CloudWatch log groups..."
    aws logs delete-log-group --log-group-name "/ecs/$stack_name" 2>/dev/null || true
    log_info "Deleted log group: /ecs/$stack_name"

    # Delete IAM role
    log_step "Deleting IAM role..."
    delete_role_with_policies "${stack_name}-task-execution-role" 2>/dev/null || true
    log_info "Deleted role: ${stack_name}-task-execution-role"

    log_success "Destroyed all resources for: $stack_name"
}

status() {
    local stack_name=${1:-}

    log_info "Checking status${stack_name:+ for stack: $stack_name}..."
    echo ""

    echo -e "${BLUE}=== ECR Repositories ===${NC}"
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
            --query 'clusters[*].{Name:clusterName,Status:status,RunningTasks:runningTasksCount,PendingTasks:pendingTasksCount}' \
            --output table 2>/dev/null || echo "No ECS cluster found"
    else
        cluster_list
    fi

    echo -e "\n${BLUE}=== Task Definitions ===${NC}"
    if [ -n "$stack_name" ]; then
        aws ecs describe-task-definition \
            --task-definition "$stack_name" \
            --query 'taskDefinition.{Family:family,Revision:revision,CPU:cpu,Memory:memory,Image:containerDefinitions[0].image}' \
            --output table 2>/dev/null || echo "No task definition found"
    else
        task_list
    fi

    echo -e "\n${BLUE}=== Running Tasks ===${NC}"
    if [ -n "$stack_name" ]; then
        local running=$(aws ecs list-tasks --cluster "$stack_name" --desired-status RUNNING --query 'taskArns' --output text 2>/dev/null)
        if [ -n "$running" ] && [ "$running" != "None" ]; then
            aws ecs describe-tasks \
                --cluster "$stack_name" \
                --tasks $running \
                --query 'tasks[*].{TaskId:taskArn,Status:lastStatus,StartedAt:startedAt}' \
                --output table
        else
            echo "No running tasks"
        fi
    else
        echo "Specify a stack name to list running tasks"
    fi

    echo -e "\n${BLUE}=== CloudWatch Log Groups ===${NC}"
    if [ -n "$stack_name" ]; then
        aws logs describe-log-groups \
            --log-group-name-prefix "/ecs/$stack_name" \
            --query 'logGroups[*].{Name:logGroupName,RetentionDays:retentionInDays}' \
            --output table 2>/dev/null || echo "No log groups found"
    else
        logs_list
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

    # Job Execution
    job-run)
        job_run "$@"
        ;;
    job-run-wait)
        job_run_wait "$@"
        ;;
    job-list)
        job_list "$@"
        ;;
    job-describe)
        job_describe "$@"
        ;;
    job-stop)
        job_stop "$@"
        ;;
    job-logs)
        job_logs "$@"
        ;;

    # IAM
    iam-create-role)
        iam_create_role "$@"
        ;;
    iam-delete-role)
        iam_delete_role "$@"
        ;;

    # CloudWatch Logs
    logs-list)
        logs_list
        ;;
    logs-tail)
        logs_tail "$@"
        ;;
    logs-delete)
        logs_delete "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
