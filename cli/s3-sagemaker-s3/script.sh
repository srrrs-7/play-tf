#!/bin/bash
set -e

# =============================================================================
# S3 → SageMaker → S3 ML Training Pipeline
# =============================================================================
# This script manages a machine learning training infrastructure:
# - S3: Input data storage and model output storage
# - SageMaker: Model training and processing
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default region
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

# =============================================================================
# Usage Function
# =============================================================================
usage() {
    cat << EOF
S3 → SageMaker → S3 ML Training Pipeline Management Script

Usage: $0 <command> [options]

Commands:
    deploy <stack-name>              Deploy the complete ML training stack
    destroy <stack-name>             Destroy all resources for the stack
    status                           Show status of all components

    S3 Commands:
    create-bucket <name> <type>      Create S3 bucket (input|output|model)
    upload-data <bucket> <local-path> Upload training data
    list-data <bucket>               List data in bucket

    SageMaker Training Commands:
    create-training-job <name> <image> <input-bucket> <output-bucket>  Create training job
    list-training-jobs               List all training jobs
    describe-training-job <name>     Describe training job status
    stop-training-job <name>         Stop training job
    download-model <job-name> <local-path>  Download trained model

    SageMaker Processing Commands:
    create-processing-job <name> <image> <input-bucket> <output-bucket>  Create processing job
    list-processing-jobs             List all processing jobs
    describe-processing-job <name>   Describe processing job status
    stop-processing-job <name>       Stop processing job

    SageMaker Notebook Commands:
    create-notebook <name>           Create notebook instance
    start-notebook <name>            Start notebook instance
    stop-notebook <name>             Stop notebook instance
    delete-notebook <name>           Delete notebook instance
    list-notebooks                   List all notebook instances
    get-notebook-url <name>          Get notebook presigned URL

    SageMaker Experiments:
    create-experiment <name>         Create experiment
    list-experiments                 List all experiments
    delete-experiment <name>         Delete experiment

Examples:
    $0 deploy my-ml-pipeline
    $0 create-training-job my-training 763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:1.12-cpu-py38 my-input-bucket my-output-bucket
    $0 create-notebook ml-notebook
    $0 status

Environment Variables:
    AWS_DEFAULT_REGION    AWS region (default: ap-northeast-1)
    AWS_PROFILE           AWS profile to use

EOF
    exit 1
}

# =============================================================================
# Logging Functions
# =============================================================================
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

# =============================================================================
# Helper Functions
# =============================================================================
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

wait_for_training_job() {
    local job_name=$1
    local max_attempts=180  # 30 minutes max
    local attempt=0

    log_info "Waiting for training job to complete..."
    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws sagemaker describe-training-job \
            --training-job-name "$job_name" \
            --query 'TrainingJobStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")

        case $status in
            Completed)
                log_info "Training job completed successfully"
                return 0
                ;;
            Failed|Stopped)
                log_error "Training job $status"
                return 1
                ;;
        esac

        echo -n "."
        sleep 10
        ((attempt++))
    done

    log_error "Timeout waiting for training job"
    return 1
}

# =============================================================================
# S3 Functions
# =============================================================================
create_bucket() {
    local name=$1
    local type=$2

    if [ -z "$name" ] || [ -z "$type" ]; then
        log_error "Bucket name and type are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local bucket_name="${name}-${type}-${account_id}"

    log_step "Creating S3 bucket: $bucket_name"

    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    log_info "S3 bucket created: $bucket_name"
}

upload_data() {
    local bucket=$1
    local local_path=$2

    if [ -z "$bucket" ] || [ -z "$local_path" ]; then
        log_error "Bucket and local path are required"
        exit 1
    fi

    log_step "Uploading data to s3://${bucket}/"
    aws s3 sync "$local_path" "s3://${bucket}/"
    log_info "Data uploaded successfully"
}

list_data() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_info "Listing data in bucket: $bucket"
    aws s3 ls "s3://${bucket}/" --recursive --human-readable
}

# =============================================================================
# SageMaker Training Functions
# =============================================================================
create_training_job() {
    local job_name=$1
    local image_uri=$2
    local input_bucket=$3
    local output_bucket=$4

    if [ -z "$job_name" ] || [ -z "$image_uri" ] || [ -z "$input_bucket" ] || [ -z "$output_bucket" ]; then
        log_error "Job name, image URI, input bucket, and output bucket are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION
    local role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"

    log_step "Creating training job: $job_name"

    aws sagemaker create-training-job \
        --training-job-name "$job_name" \
        --algorithm-specification "{
            \"TrainingImage\": \"$image_uri\",
            \"TrainingInputMode\": \"File\"
        }" \
        --role-arn "$role_arn" \
        --input-data-config "[{
            \"ChannelName\": \"training\",
            \"DataSource\": {
                \"S3DataSource\": {
                    \"S3DataType\": \"S3Prefix\",
                    \"S3Uri\": \"s3://${input_bucket}/training/\",
                    \"S3DataDistributionType\": \"FullyReplicated\"
                }
            }
        }]" \
        --output-data-config "{
            \"S3OutputPath\": \"s3://${output_bucket}/output/\"
        }" \
        --resource-config '{
            "InstanceType": "ml.m5.large",
            "InstanceCount": 1,
            "VolumeSizeInGB": 50
        }' \
        --stopping-condition '{"MaxRuntimeInSeconds": 86400}' \
        --output json | jq '.'

    log_info "Training job created: $job_name"
}

list_training_jobs() {
    log_info "Listing training jobs..."
    aws sagemaker list-training-jobs \
        --query 'TrainingJobSummaries[].{Name:TrainingJobName,Status:TrainingJobStatus,CreationTime:CreationTime}' \
        --output table
}

describe_training_job() {
    local job_name=$1

    if [ -z "$job_name" ]; then
        log_error "Job name is required"
        exit 1
    fi

    log_info "Describing training job: $job_name"
    aws sagemaker describe-training-job \
        --training-job-name "$job_name" \
        --output json | jq '.'
}

stop_training_job() {
    local job_name=$1

    if [ -z "$job_name" ]; then
        log_error "Job name is required"
        exit 1
    fi

    log_step "Stopping training job: $job_name"
    aws sagemaker stop-training-job --training-job-name "$job_name"
    log_info "Training job stop initiated"
}

download_model() {
    local job_name=$1
    local local_path=$2

    if [ -z "$job_name" ] || [ -z "$local_path" ]; then
        log_error "Job name and local path are required"
        exit 1
    fi

    # Get model artifact location
    local model_uri=$(aws sagemaker describe-training-job \
        --training-job-name "$job_name" \
        --query 'ModelArtifacts.S3ModelArtifacts' \
        --output text)

    log_step "Downloading model from: $model_uri"
    aws s3 cp "$model_uri" "$local_path"
    log_info "Model downloaded to: $local_path"
}

# =============================================================================
# SageMaker Processing Functions
# =============================================================================
create_processing_job() {
    local job_name=$1
    local image_uri=$2
    local input_bucket=$3
    local output_bucket=$4

    if [ -z "$job_name" ] || [ -z "$image_uri" ] || [ -z "$input_bucket" ] || [ -z "$output_bucket" ]; then
        log_error "Job name, image URI, input bucket, and output bucket are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"

    log_step "Creating processing job: $job_name"

    aws sagemaker create-processing-job \
        --processing-job-name "$job_name" \
        --processing-resources '{
            "ClusterConfig": {
                "InstanceCount": 1,
                "InstanceType": "ml.m5.large",
                "VolumeSizeInGB": 50
            }
        }' \
        --app-specification "{
            \"ImageUri\": \"$image_uri\"
        }" \
        --role-arn "$role_arn" \
        --processing-inputs "[{
            \"InputName\": \"input\",
            \"S3Input\": {
                \"S3Uri\": \"s3://${input_bucket}/\",
                \"LocalPath\": \"/opt/ml/processing/input\",
                \"S3DataType\": \"S3Prefix\",
                \"S3InputMode\": \"File\"
            }
        }]" \
        --processing-output-config "{
            \"Outputs\": [{
                \"OutputName\": \"output\",
                \"S3Output\": {
                    \"S3Uri\": \"s3://${output_bucket}/processed/\",
                    \"LocalPath\": \"/opt/ml/processing/output\",
                    \"S3UploadMode\": \"EndOfJob\"
                }
            }]
        }" \
        --output json | jq '.'

    log_info "Processing job created: $job_name"
}

list_processing_jobs() {
    log_info "Listing processing jobs..."
    aws sagemaker list-processing-jobs \
        --query 'ProcessingJobSummaries[].{Name:ProcessingJobName,Status:ProcessingJobStatus,CreationTime:CreationTime}' \
        --output table
}

describe_processing_job() {
    local job_name=$1

    if [ -z "$job_name" ]; then
        log_error "Job name is required"
        exit 1
    fi

    log_info "Describing processing job: $job_name"
    aws sagemaker describe-processing-job \
        --processing-job-name "$job_name" \
        --output json | jq '.'
}

stop_processing_job() {
    local job_name=$1

    if [ -z "$job_name" ]; then
        log_error "Job name is required"
        exit 1
    fi

    log_step "Stopping processing job: $job_name"
    aws sagemaker stop-processing-job --processing-job-name "$job_name"
    log_info "Processing job stop initiated"
}

# =============================================================================
# SageMaker Notebook Functions
# =============================================================================
create_notebook() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Notebook name is required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"

    log_step "Creating notebook instance: $name"

    aws sagemaker create-notebook-instance \
        --notebook-instance-name "$name" \
        --instance-type "ml.t3.medium" \
        --role-arn "$role_arn" \
        --volume-size-in-gb 20 \
        --output json | jq '.'

    log_info "Notebook instance created. Waiting for it to be InService..."
    aws sagemaker wait notebook-instance-in-service --notebook-instance-name "$name"
    log_info "Notebook instance is ready: $name"
}

start_notebook() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Notebook name is required"
        exit 1
    fi

    log_step "Starting notebook instance: $name"
    aws sagemaker start-notebook-instance --notebook-instance-name "$name"

    log_info "Waiting for notebook to start..."
    aws sagemaker wait notebook-instance-in-service --notebook-instance-name "$name"
    log_info "Notebook instance started"
}

stop_notebook() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Notebook name is required"
        exit 1
    fi

    log_step "Stopping notebook instance: $name"
    aws sagemaker stop-notebook-instance --notebook-instance-name "$name"

    log_info "Waiting for notebook to stop..."
    aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$name"
    log_info "Notebook instance stopped"
}

delete_notebook() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Notebook name is required"
        exit 1
    fi

    log_warn "This will delete the notebook instance: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Stop if running
    local status=$(aws sagemaker describe-notebook-instance \
        --notebook-instance-name "$name" \
        --query 'NotebookInstanceStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [ "$status" == "InService" ]; then
        log_step "Stopping notebook first..."
        aws sagemaker stop-notebook-instance --notebook-instance-name "$name"
        aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$name"
    fi

    log_step "Deleting notebook instance: $name"
    aws sagemaker delete-notebook-instance --notebook-instance-name "$name"
    log_info "Notebook instance deleted"
}

list_notebooks() {
    log_info "Listing notebook instances..."
    aws sagemaker list-notebook-instances \
        --query 'NotebookInstances[].{Name:NotebookInstanceName,Status:NotebookInstanceStatus,InstanceType:InstanceType}' \
        --output table
}

get_notebook_url() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Notebook name is required"
        exit 1
    fi

    log_info "Getting presigned URL for notebook: $name"
    aws sagemaker create-presigned-notebook-instance-url \
        --notebook-instance-name "$name" \
        --query 'AuthorizedUrl' \
        --output text
}

# =============================================================================
# SageMaker Experiments Functions
# =============================================================================
create_experiment() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Experiment name is required"
        exit 1
    fi

    log_step "Creating experiment: $name"

    aws sagemaker create-experiment \
        --experiment-name "$name" \
        --description "ML experiment: $name" \
        --output json | jq '.'

    log_info "Experiment created: $name"
}

list_experiments() {
    log_info "Listing experiments..."
    aws sagemaker list-experiments \
        --query 'ExperimentSummaries[].{Name:ExperimentName,CreationTime:CreationTime}' \
        --output table
}

delete_experiment() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Experiment name is required"
        exit 1
    fi

    log_warn "This will delete the experiment: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting experiment: $name"
    aws sagemaker delete-experiment --experiment-name "$name"
    log_info "Experiment deleted"
}

# =============================================================================
# Deploy/Destroy Functions
# =============================================================================
deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 deploy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION

    log_info "Deploying ML training stack: $stack_name"
    echo ""

    # Step 1: Create IAM role for SageMaker
    log_step "Step 1: Creating IAM role for SageMaker..."

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "sagemaker.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "sagemaker-execution-role" \
        --assume-role-policy-document "$trust_policy" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "sagemaker-execution-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "sagemaker-execution-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>/dev/null || true

    sleep 10
    log_info "IAM role created: sagemaker-execution-role"
    echo ""

    # Step 2: Create S3 buckets
    log_step "Step 2: Creating S3 buckets..."

    local input_bucket="${stack_name}-input-${account_id}"
    local output_bucket="${stack_name}-output-${account_id}"
    local model_bucket="${stack_name}-models-${account_id}"

    for bucket in $input_bucket $output_bucket $model_bucket; do
        if [ "$DEFAULT_REGION" == "us-east-1" ]; then
            aws s3api create-bucket --bucket "$bucket" 2>/dev/null || true
        else
            aws s3api create-bucket \
                --bucket "$bucket" \
                --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || true
        fi

        aws s3api put-bucket-versioning \
            --bucket "$bucket" \
            --versioning-configuration Status=Enabled
    done

    log_info "S3 buckets created: $input_bucket, $output_bucket, $model_bucket"
    echo ""

    # Step 3: Create sample training data structure
    log_step "Step 3: Creating sample data structure..."

    aws s3api put-object --bucket "$input_bucket" --key "training/.gitkeep" --body /dev/null
    aws s3api put-object --bucket "$input_bucket" --key "validation/.gitkeep" --body /dev/null
    aws s3api put-object --bucket "$input_bucket" --key "test/.gitkeep" --body /dev/null

    log_info "Sample folder structure created"
    echo ""

    # Step 4: Create SageMaker experiment
    log_step "Step 4: Creating SageMaker experiment..."

    aws sagemaker create-experiment \
        --experiment-name "${stack_name}-experiment" \
        --description "ML experiments for ${stack_name}" \
        --output json >/dev/null 2>&1 || true

    log_info "Experiment created: ${stack_name}-experiment"
    echo ""

    log_info "================================================"
    log_info "ML training stack deployed successfully!"
    log_info "================================================"
    echo ""
    log_info "Stack Name: $stack_name"
    log_info "Input Bucket: $input_bucket"
    log_info "Output Bucket: $output_bucket"
    log_info "Model Bucket: $model_bucket"
    log_info "IAM Role: sagemaker-execution-role"
    log_info "Experiment: ${stack_name}-experiment"
    echo ""
    log_info "Next Steps:"
    log_info "1. Upload training data: $0 upload-data $input_bucket /path/to/data"
    log_info "2. Create a training job:"
    log_info "   $0 create-training-job my-job <image-uri> $input_bucket $output_bucket"
    log_info "3. Or create a notebook: $0 create-notebook ${stack_name}-notebook"
    echo ""
    log_info "Common SageMaker container images:"
    log_info "- PyTorch: 763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-training:1.12-cpu-py38"
    log_info "- TensorFlow: 763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-training:2.11-cpu-py39"
    log_info "- SKLearn: 683313688378.dkr.ecr.${region}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 destroy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)

    log_warn "This will destroy all resources for stack: $stack_name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Stop and delete notebook instances
    log_step "Checking for notebook instances..."
    local notebooks=$(aws sagemaker list-notebook-instances \
        --query "NotebookInstances[?starts_with(NotebookInstanceName, '${stack_name}')].NotebookInstanceName" \
        --output text 2>/dev/null || echo "")

    for notebook in $notebooks; do
        local status=$(aws sagemaker describe-notebook-instance \
            --notebook-instance-name "$notebook" \
            --query 'NotebookInstanceStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$status" == "InService" ]; then
            log_step "Stopping notebook: $notebook"
            aws sagemaker stop-notebook-instance --notebook-instance-name "$notebook"
            aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$notebook"
        fi

        log_step "Deleting notebook: $notebook"
        aws sagemaker delete-notebook-instance --notebook-instance-name "$notebook" 2>/dev/null || true
    done

    # Delete experiment
    log_step "Deleting experiment..."
    aws sagemaker delete-experiment --experiment-name "${stack_name}-experiment" 2>/dev/null || true

    # Delete S3 buckets
    log_step "Deleting S3 buckets..."
    local input_bucket="${stack_name}-input-${account_id}"
    local output_bucket="${stack_name}-output-${account_id}"
    local model_bucket="${stack_name}-models-${account_id}"

    for bucket in $input_bucket $output_bucket $model_bucket; do
        aws s3 rb "s3://${bucket}" --force 2>/dev/null || true
    done

    log_info "Stack destroyed successfully: $stack_name"
    log_warn "Note: SageMaker execution role was not deleted (may be used by other stacks)"
}

status() {
    log_info "=== ML Training Stack Status ==="
    echo ""

    log_info "Training Jobs:"
    aws sagemaker list-training-jobs \
        --query 'TrainingJobSummaries[].{Name:TrainingJobName,Status:TrainingJobStatus,Created:CreationTime}' \
        --output table 2>/dev/null || echo "No training jobs found"
    echo ""

    log_info "Processing Jobs:"
    aws sagemaker list-processing-jobs \
        --query 'ProcessingJobSummaries[].{Name:ProcessingJobName,Status:ProcessingJobStatus,Created:CreationTime}' \
        --output table 2>/dev/null || echo "No processing jobs found"
    echo ""

    log_info "Notebook Instances:"
    aws sagemaker list-notebook-instances \
        --query 'NotebookInstances[].{Name:NotebookInstanceName,Status:NotebookInstanceStatus,Type:InstanceType}' \
        --output table 2>/dev/null || echo "No notebook instances found"
    echo ""

    log_info "Experiments:"
    aws sagemaker list-experiments \
        --query 'ExperimentSummaries[].{Name:ExperimentName,Created:CreationTime}' \
        --output table 2>/dev/null || echo "No experiments found"
}

# =============================================================================
# Main
# =============================================================================
check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    deploy)
        deploy "$@"
        ;;
    destroy)
        destroy "$@"
        ;;
    status)
        status
        ;;
    create-bucket)
        create_bucket "$@"
        ;;
    upload-data)
        upload_data "$@"
        ;;
    list-data)
        list_data "$@"
        ;;
    create-training-job)
        create_training_job "$@"
        ;;
    list-training-jobs)
        list_training_jobs
        ;;
    describe-training-job)
        describe_training_job "$@"
        ;;
    stop-training-job)
        stop_training_job "$@"
        ;;
    download-model)
        download_model "$@"
        ;;
    create-processing-job)
        create_processing_job "$@"
        ;;
    list-processing-jobs)
        list_processing_jobs
        ;;
    describe-processing-job)
        describe_processing_job "$@"
        ;;
    stop-processing-job)
        stop_processing_job "$@"
        ;;
    create-notebook)
        create_notebook "$@"
        ;;
    start-notebook)
        start_notebook "$@"
        ;;
    stop-notebook)
        stop_notebook "$@"
        ;;
    delete-notebook)
        delete_notebook "$@"
        ;;
    list-notebooks)
        list_notebooks
        ;;
    get-notebook-url)
        get_notebook_url "$@"
        ;;
    create-experiment)
        create_experiment "$@"
        ;;
    list-experiments)
        list_experiments
        ;;
    delete-experiment)
        delete_experiment "$@"
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
