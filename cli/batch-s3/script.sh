#!/bin/bash

set -e

# AWS Batch → S3 Architecture Script
# Provides operations for batch processing jobs with S3 storage

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
    echo "AWS Batch → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy batch processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "Compute Environment:"
    echo "  compute-create <name> [type]               - Create compute environment (FARGATE/EC2)"
    echo "  compute-delete <name>                      - Delete compute environment"
    echo "  compute-list                               - List compute environments"
    echo "  compute-describe <name>                    - Describe compute environment"
    echo ""
    echo "Job Queue:"
    echo "  queue-create <name> <compute-env>          - Create job queue"
    echo "  queue-delete <name>                        - Delete job queue"
    echo "  queue-list                                 - List job queues"
    echo "  queue-describe <name>                      - Describe job queue"
    echo ""
    echo "Job Definition:"
    echo "  jobdef-create <name> <image> <bucket>      - Create job definition"
    echo "  jobdef-delete <name>                       - Delete job definition"
    echo "  jobdef-list                                - List job definitions"
    echo ""
    echo "Jobs:"
    echo "  job-submit <queue> <jobdef> <name> [params] - Submit job"
    echo "  job-list <queue>                           - List jobs"
    echo "  job-describe <job-id>                      - Describe job"
    echo "  job-cancel <job-id>                        - Cancel job"
    echo "  job-logs <job-id>                          - View job logs"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  bucket-list                                - List buckets"
    echo "  object-list <bucket> [prefix]              - List objects"
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

get_default_security_group() {
    local vpc_id=$(get_default_vpc)
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text
}

# Compute Environment Functions
compute_create() {
    local name=$1
    local type=${2:-"FARGATE"}

    [ -z "$name" ] && { log_error "Compute environment name required"; exit 1; }

    log_step "Creating compute environment: $name"
    local account_id=$(get_account_id)
    local subnets=$(get_default_subnets)
    local sg=$(get_default_security_group)

    # Create service role if not exists
    local service_role="${name}-batch-service-role"
    local service_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"batch.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$service_role" --assume-role-policy-document "$service_trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$service_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole 2>/dev/null || true

    sleep 5

    local subnet_array=$(echo "$subnets" | tr ',' '\n' | head -2 | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')

    if [ "$type" == "FARGATE" ]; then
        aws batch create-compute-environment \
            --compute-environment-name "$name" \
            --type MANAGED \
            --state ENABLED \
            --compute-resources "{
                \"type\": \"FARGATE\",
                \"maxvCpus\": 16,
                \"subnets\": [$subnet_array],
                \"securityGroupIds\": [\"$sg\"]
            }"
    else
        aws batch create-compute-environment \
            --compute-environment-name "$name" \
            --type MANAGED \
            --state ENABLED \
            --compute-resources "{
                \"type\": \"EC2\",
                \"minvCpus\": 0,
                \"maxvCpus\": 16,
                \"desiredvCpus\": 0,
                \"instanceTypes\": [\"optimal\"],
                \"subnets\": [$subnet_array],
                \"securityGroupIds\": [\"$sg\"]
            }"
    fi

    log_info "Compute environment created (may take a few minutes to become VALID)"
}

compute_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Compute environment name required"; exit 1; }

    # Disable first
    aws batch update-compute-environment --compute-environment "$name" --state DISABLED 2>/dev/null || true
    sleep 5

    aws batch delete-compute-environment --compute-environment "$name"
    log_info "Compute environment deleted"
}

compute_list() {
    aws batch describe-compute-environments --query 'computeEnvironments[].{Name:computeEnvironmentName,State:state,Status:status,Type:type}' --output table
}

compute_describe() {
    local name=$1
    [ -z "$name" ] && { log_error "Compute environment name required"; exit 1; }
    aws batch describe-compute-environments --compute-environments "$name" --output json
}

# Job Queue Functions
queue_create() {
    local name=$1
    local compute_env=$2

    if [ -z "$name" ] || [ -z "$compute_env" ]; then
        log_error "Queue name and compute environment required"
        exit 1
    fi

    log_step "Creating job queue: $name"
    aws batch create-job-queue \
        --job-queue-name "$name" \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order "order=1,computeEnvironment=$compute_env"

    log_info "Job queue created"
}

queue_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }

    # Disable first
    aws batch update-job-queue --job-queue "$name" --state DISABLED 2>/dev/null || true
    sleep 5

    aws batch delete-job-queue --job-queue "$name"
    log_info "Job queue deleted"
}

queue_list() {
    aws batch describe-job-queues --query 'jobQueues[].{Name:jobQueueName,State:state,Status:status}' --output table
}

queue_describe() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }
    aws batch describe-job-queues --job-queues "$name" --output json
}

# Job Definition Functions
jobdef_create() {
    local name=$1
    local image=$2
    local bucket=$3

    if [ -z "$name" ] || [ -z "$image" ] || [ -z "$bucket" ]; then
        log_error "Job definition name, container image, and S3 bucket required"
        exit 1
    fi

    log_step "Creating job definition: $name"
    local account_id=$(get_account_id)

    # Create execution role
    local exec_role="${name}-batch-exec-role"
    local exec_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$exec_role" --assume-role-policy-document "$exec_trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$exec_role" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

    # Create job role with S3 access
    local job_role="${name}-batch-job-role"
    local job_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$job_role" --assume-role-policy-document "$job_trust" 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListBucket"
        ],
        "Resource": [
            "arn:aws:s3:::$bucket",
            "arn:aws:s3:::$bucket/*"
        ]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$job_role" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    sleep 5

    aws batch register-job-definition \
        --job-definition-name "$name" \
        --type container \
        --platform-capabilities FARGATE \
        --container-properties "{
            \"image\": \"$image\",
            \"resourceRequirements\": [
                {\"type\": \"VCPU\", \"value\": \"0.5\"},
                {\"type\": \"MEMORY\", \"value\": \"1024\"}
            ],
            \"executionRoleArn\": \"arn:aws:iam::$account_id:role/$exec_role\",
            \"jobRoleArn\": \"arn:aws:iam::$account_id:role/$job_role\",
            \"environment\": [
                {\"name\": \"S3_BUCKET\", \"value\": \"$bucket\"},
                {\"name\": \"AWS_REGION\", \"value\": \"$DEFAULT_REGION\"}
            ],
            \"logConfiguration\": {
                \"logDriver\": \"awslogs\",
                \"options\": {
                    \"awslogs-group\": \"/aws/batch/$name\",
                    \"awslogs-region\": \"$DEFAULT_REGION\",
                    \"awslogs-stream-prefix\": \"batch\",
                    \"awslogs-create-group\": \"true\"
                }
            }
        }"

    log_info "Job definition created"
}

jobdef_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Job definition name required"; exit 1; }

    # Get all revisions
    local revisions=$(aws batch describe-job-definitions --job-definition-name "$name" --status ACTIVE --query 'jobDefinitions[].jobDefinitionArn' --output text)
    for rev in $revisions; do
        aws batch deregister-job-definition --job-definition "$rev"
    done
    log_info "Job definition deleted"
}

jobdef_list() {
    aws batch describe-job-definitions --status ACTIVE --query 'jobDefinitions[].{Name:jobDefinitionName,Revision:revision,Status:status}' --output table
}

# Job Functions
job_submit() {
    local queue=$1
    local jobdef=$2
    local name=$3
    local params=${4:-"{}"}

    if [ -z "$queue" ] || [ -z "$jobdef" ] || [ -z "$name" ]; then
        log_error "Queue, job definition, and job name required"
        exit 1
    fi

    log_step "Submitting job: $name"

    local job_id=$(aws batch submit-job \
        --job-name "$name" \
        --job-queue "$queue" \
        --job-definition "$jobdef" \
        --container-overrides "{
            \"environment\": [
                {\"name\": \"JOB_PARAMS\", \"value\": \"$params\"}
            ]
        }" \
        --query 'jobId' --output text)

    log_info "Job submitted: $job_id"
    echo "$job_id"
}

job_list() {
    local queue=$1
    [ -z "$queue" ] && { log_error "Queue name required"; exit 1; }

    echo -e "${BLUE}=== Running/Pending Jobs ===${NC}"
    aws batch list-jobs --job-queue "$queue" --job-status RUNNING --query 'jobSummaryList[].{Name:jobName,Id:jobId,Status:status,CreatedAt:createdAt}' --output table 2>/dev/null || true
    aws batch list-jobs --job-queue "$queue" --job-status PENDING --query 'jobSummaryList[].{Name:jobName,Id:jobId,Status:status,CreatedAt:createdAt}' --output table 2>/dev/null || true

    echo -e "\n${BLUE}=== Recent Completed Jobs ===${NC}"
    aws batch list-jobs --job-queue "$queue" --job-status SUCCEEDED --query 'jobSummaryList[].{Name:jobName,Id:jobId,Status:status}' --output table 2>/dev/null || true
}

job_describe() {
    local job_id=$1
    [ -z "$job_id" ] && { log_error "Job ID required"; exit 1; }
    aws batch describe-jobs --jobs "$job_id" --output json
}

job_cancel() {
    local job_id=$1
    [ -z "$job_id" ] && { log_error "Job ID required"; exit 1; }
    aws batch cancel-job --job-id "$job_id" --reason "Cancelled by user"
    log_info "Job cancelled"
}

job_logs() {
    local job_id=$1
    [ -z "$job_id" ] && { log_error "Job ID required"; exit 1; }

    local log_stream=$(aws batch describe-jobs --jobs "$job_id" --query 'jobs[0].container.logStreamName' --output text)

    if [ -n "$log_stream" ] && [ "$log_stream" != "None" ]; then
        local log_group=$(aws batch describe-jobs --jobs "$job_id" --query 'jobs[0].container.logConfiguration.options."awslogs-group"' --output text)
        aws logs get-log-events --log-group-name "$log_group" --log-stream-name "$log_stream" --query 'events[].message' --output text
    else
        log_warn "No logs available yet"
    fi
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating bucket: $name"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket --bucket "$name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi
    log_info "Bucket created"
}

bucket_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_warn "Deleting bucket: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

bucket_list() {
    aws s3api list-buckets --query 'Buckets[].Name' --output table
}

object_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    else
        aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    fi
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying AWS Batch → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-batch-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket already exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket already exists"
    fi

    # Create compute environment
    log_step "Creating compute environment..."
    local subnets=$(get_default_subnets)
    local sg=$(get_default_security_group)
    local subnet_array=$(echo "$subnets" | tr ',' '\n' | head -2 | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')

    aws batch create-compute-environment \
        --compute-environment-name "${name}-compute" \
        --type MANAGED \
        --state ENABLED \
        --compute-resources "{
            \"type\": \"FARGATE\",
            \"maxvCpus\": 16,
            \"subnets\": [$subnet_array],
            \"securityGroupIds\": [\"$sg\"]
        }" 2>/dev/null || log_info "Compute environment already exists"

    # Wait for compute environment
    log_info "Waiting for compute environment to become VALID..."
    for i in {1..30}; do
        local status=$(aws batch describe-compute-environments --compute-environments "${name}-compute" --query 'computeEnvironments[0].status' --output text)
        if [ "$status" == "VALID" ]; then
            break
        fi
        sleep 10
    done

    # Create job queue
    log_step "Creating job queue..."
    aws batch create-job-queue \
        --job-queue-name "${name}-queue" \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order "order=1,computeEnvironment=${name}-compute" 2>/dev/null || log_info "Job queue already exists"

    # Wait for job queue
    log_info "Waiting for job queue to become VALID..."
    for i in {1..20}; do
        local status=$(aws batch describe-job-queues --job-queues "${name}-queue" --query 'jobQueues[0].status' --output text)
        if [ "$status" == "VALID" ]; then
            break
        fi
        sleep 5
    done

    # Create IAM roles
    log_step "Creating IAM roles..."
    local exec_role="${name}-batch-exec-role"
    local exec_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$exec_role" --assume-role-policy-document "$exec_trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$exec_role" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

    local job_role="${name}-batch-job-role"
    local job_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$job_role" --assume-role-policy-document "$job_trust" 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListBucket"
        ],
        "Resource": [
            "arn:aws:s3:::$bucket_name",
            "arn:aws:s3:::$bucket_name/*"
        ]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$job_role" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    sleep 5

    # Create job definition
    log_step "Creating job definition..."
    aws batch register-job-definition \
        --job-definition-name "${name}-job" \
        --type container \
        --platform-capabilities FARGATE \
        --container-properties "{
            \"image\": \"amazon/aws-cli:latest\",
            \"resourceRequirements\": [
                {\"type\": \"VCPU\", \"value\": \"0.5\"},
                {\"type\": \"MEMORY\", \"value\": \"1024\"}
            ],
            \"executionRoleArn\": \"arn:aws:iam::$account_id:role/$exec_role\",
            \"jobRoleArn\": \"arn:aws:iam::$account_id:role/$job_role\",
            \"command\": [
                \"sh\", \"-c\",
                \"echo Processing batch job... && echo Job params: \$JOB_PARAMS && TIMESTAMP=\$(date +%Y%m%d-%H%M%S) && echo '{\\\"jobId\\\": \\\"\$AWS_BATCH_JOB_ID\\\", \\\"timestamp\\\": \\\"'\$TIMESTAMP'\\\", \\\"params\\\": '\$JOB_PARAMS', \\\"status\\\": \\\"completed\\\"}' > /tmp/result.json && aws s3 cp /tmp/result.json s3://\$S3_BUCKET/results/\$TIMESTAMP-result.json && echo Job completed successfully\"
            ],
            \"environment\": [
                {\"name\": \"S3_BUCKET\", \"value\": \"$bucket_name\"},
                {\"name\": \"AWS_REGION\", \"value\": \"$DEFAULT_REGION\"},
                {\"name\": \"JOB_PARAMS\", \"value\": \"{}\"}
            ],
            \"logConfiguration\": {
                \"logDriver\": \"awslogs\",
                \"options\": {
                    \"awslogs-group\": \"/aws/batch/${name}-job\",
                    \"awslogs-region\": \"$DEFAULT_REGION\",
                    \"awslogs-stream-prefix\": \"batch\",
                    \"awslogs-create-group\": \"true\"
                }
            }
        }" 2>/dev/null || log_info "Job definition already exists"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Compute Environment: ${name}-compute"
    echo "Job Queue: ${name}-queue"
    echo "Job Definition: ${name}-job"
    echo ""
    echo "Submit a test job:"
    echo "  aws batch submit-job \\"
    echo "    --job-name 'test-job' \\"
    echo "    --job-queue '${name}-queue' \\"
    echo "    --job-definition '${name}-job'"
    echo ""
    echo "Check job status:"
    echo "  aws batch list-jobs --job-queue '${name}-queue' --job-status RUNNING"
    echo ""
    echo "Check S3 for results:"
    echo "  aws s3 ls s3://$bucket_name/results/"
    echo ""
    echo "View job logs:"
    echo "  aws logs tail /aws/batch/${name}-job --follow"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Cancel any running jobs
    log_step "Cancelling running jobs..."
    local jobs=$(aws batch list-jobs --job-queue "${name}-queue" --job-status RUNNING --query 'jobSummaryList[].jobId' --output text 2>/dev/null)
    for job in $jobs; do
        aws batch cancel-job --job-id "$job" --reason "Stack deletion" 2>/dev/null || true
    done

    # Deregister job definitions
    log_step "Deregistering job definitions..."
    local job_defs=$(aws batch describe-job-definitions --job-definition-name "${name}-job" --status ACTIVE --query 'jobDefinitions[].jobDefinitionArn' --output text 2>/dev/null)
    for jd in $job_defs; do
        aws batch deregister-job-definition --job-definition "$jd" 2>/dev/null || true
    done

    # Disable and delete job queue
    log_step "Deleting job queue..."
    aws batch update-job-queue --job-queue "${name}-queue" --state DISABLED 2>/dev/null || true
    sleep 10
    aws batch delete-job-queue --job-queue "${name}-queue" 2>/dev/null || true

    # Wait for queue deletion
    for i in {1..20}; do
        local status=$(aws batch describe-job-queues --job-queues "${name}-queue" --query 'jobQueues[0].status' --output text 2>/dev/null)
        if [ -z "$status" ] || [ "$status" == "None" ]; then
            break
        fi
        sleep 5
    done

    # Disable and delete compute environment
    log_step "Deleting compute environment..."
    aws batch update-compute-environment --compute-environment "${name}-compute" --state DISABLED 2>/dev/null || true
    sleep 10
    aws batch delete-compute-environment --compute-environment "${name}-compute" 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-batch-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete CloudWatch log group
    aws logs delete-log-group --log-group-name "/aws/batch/${name}-job" 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-batch-job-role" --policy-name "${name}-s3-access" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-batch-job-role" 2>/dev/null || true

    aws iam detach-role-policy --role-name "${name}-batch-exec-role" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true
    aws iam delete-role --role-name "${name}-batch-exec-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Compute Environments ===${NC}"
    compute_list
    echo -e "\n${BLUE}=== Job Queues ===${NC}"
    queue_list
    echo -e "\n${BLUE}=== Job Definitions ===${NC}"
    jobdef_list
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    bucket_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    compute-create) compute_create "$@" ;;
    compute-delete) compute_delete "$@" ;;
    compute-list) compute_list ;;
    compute-describe) compute_describe "$@" ;;
    queue-create) queue_create "$@" ;;
    queue-delete) queue_delete "$@" ;;
    queue-list) queue_list ;;
    queue-describe) queue_describe "$@" ;;
    jobdef-create) jobdef_create "$@" ;;
    jobdef-delete) jobdef_delete "$@" ;;
    jobdef-list) jobdef_list ;;
    job-submit) job_submit "$@" ;;
    job-list) job_list "$@" ;;
    job-describe) job_describe "$@" ;;
    job-cancel) job_cancel "$@" ;;
    job-logs) job_logs "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    object-list) object_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
