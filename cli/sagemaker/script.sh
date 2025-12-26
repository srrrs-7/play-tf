#!/bin/bash
# =============================================================================
# AWS SageMaker CLI Script
# =============================================================================
# This script manages SageMaker resources:
#   - Training Jobs
#   - Processing Jobs
#   - Notebook Instances
#   - Models
#   - Endpoints (Inference)
#   - Experiments
#   - Model Registry
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
DEFAULT_INSTANCE_TYPE="ml.m5.large"
DEFAULT_NOTEBOOK_INSTANCE_TYPE="ml.t3.medium"
DEFAULT_VOLUME_SIZE=50
DEFAULT_MAX_RUNTIME=86400

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "AWS SageMaker Management Script"
    echo ""
    echo "Commands:"
    echo ""
    echo "  === Full Stack (Terraform) ==="
    echo "  tf-init                                - Initialize Terraform"
    echo "  tf-plan <stack-name>                   - Plan infrastructure"
    echo "  tf-apply <stack-name>                  - Deploy infrastructure"
    echo "  tf-destroy <stack-name>                - Destroy infrastructure"
    echo "  tf-output                              - Show Terraform outputs"
    echo ""
    echo "  === Training Jobs ==="
    echo "  training-create <name> <image> <s3-input> <s3-output> [role-arn]"
    echo "                                         - Create training job"
    echo "  training-list [--status <status>]      - List training jobs"
    echo "  training-describe <name>               - Describe training job"
    echo "  training-stop <name>                   - Stop training job"
    echo "  training-logs <name>                   - View training logs"
    echo ""
    echo "  === Processing Jobs ==="
    echo "  processing-create <name> <image> <s3-input> <s3-output> [role-arn]"
    echo "                                         - Create processing job"
    echo "  processing-list [--status <status>]    - List processing jobs"
    echo "  processing-describe <name>             - Describe processing job"
    echo "  processing-stop <name>                 - Stop processing job"
    echo ""
    echo "  === Notebook Instances ==="
    echo "  notebook-create <name> [role-arn]      - Create notebook instance"
    echo "  notebook-list                          - List notebook instances"
    echo "  notebook-describe <name>               - Describe notebook instance"
    echo "  notebook-start <name>                  - Start notebook instance"
    echo "  notebook-stop <name>                   - Stop notebook instance"
    echo "  notebook-delete <name>                 - Delete notebook instance"
    echo "  notebook-url <name>                    - Get presigned URL"
    echo ""
    echo "  === Models ==="
    echo "  model-create <name> <image> <model-s3-uri> [role-arn]"
    echo "                                         - Create model"
    echo "  model-list                             - List models"
    echo "  model-describe <name>                  - Describe model"
    echo "  model-delete <name>                    - Delete model"
    echo ""
    echo "  === Endpoints ==="
    echo "  endpoint-config-create <name> <model-name> [instance-type] [count]"
    echo "                                         - Create endpoint configuration"
    echo "  endpoint-config-list                   - List endpoint configurations"
    echo "  endpoint-config-delete <name>          - Delete endpoint configuration"
    echo "  endpoint-create <name> <config-name>   - Create endpoint"
    echo "  endpoint-list                          - List endpoints"
    echo "  endpoint-describe <name>               - Describe endpoint"
    echo "  endpoint-update <name> <config-name>   - Update endpoint"
    echo "  endpoint-delete <name>                 - Delete endpoint"
    echo "  endpoint-invoke <name> <payload>       - Invoke endpoint"
    echo ""
    echo "  === Experiments ==="
    echo "  experiment-create <name> [description] - Create experiment"
    echo "  experiment-list                        - List experiments"
    echo "  experiment-describe <name>             - Describe experiment"
    echo "  experiment-delete <name>               - Delete experiment"
    echo "  trial-create <name> <experiment>       - Create trial"
    echo "  trial-list <experiment>                - List trials in experiment"
    echo "  trial-delete <name>                    - Delete trial"
    echo ""
    echo "  === Model Registry ==="
    echo "  model-package-group-create <name>      - Create model package group"
    echo "  model-package-group-list               - List model package groups"
    echo "  model-package-group-delete <name>      - Delete model package group"
    echo "  model-package-list <group>             - List model packages"
    echo ""
    echo "  === IAM Roles ==="
    echo "  role-create <name>                     - Create SageMaker execution role"
    echo "  role-delete <name>                     - Delete SageMaker execution role"
    echo "  role-list                              - List SageMaker roles"
    echo ""
    echo "  === Utilities ==="
    echo "  status                                 - Show status of all resources"
    echo "  images [framework]                     - List available container images"
    echo ""
    echo "Options:"
    echo "  --region <region>                      - AWS region (default: ap-northeast-1)"
    echo "  --instance-type <type>                 - Instance type (default: ml.m5.large)"
    echo "  --volume-size <gb>                     - Volume size in GB (default: 50)"
    echo ""
    echo "Examples:"
    echo "  # Deploy infrastructure with Terraform"
    echo "  $0 tf-apply my-ml-project"
    echo ""
    echo "  # Create a training job"
    echo "  $0 training-create my-job 763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:2.0-cpu-py310 s3://input-bucket/data s3://output-bucket/models"
    echo ""
    echo "  # Create a notebook instance"
    echo "  $0 notebook-create my-notebook"
    echo ""
    echo "  # Create and deploy a model endpoint"
    echo "  $0 model-create my-model 763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:2.0-cpu-py310 s3://bucket/model.tar.gz"
    echo "  $0 endpoint-config-create my-config my-model ml.m5.large 1"
    echo "  $0 endpoint-create my-endpoint my-config"
    echo ""
    exit 1
}

# =============================================================================
# Terraform Functions
# =============================================================================
tf_init() {
    log_step "Initializing Terraform..."
    cd "$SCRIPT_DIR/tf"
    terraform init
    log_success "Terraform initialized"
}

tf_plan() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_step "Planning infrastructure for: $stack_name"
    cd "$SCRIPT_DIR/tf"

    if [ ! -f "terraform.tfvars" ]; then
        log_warn "terraform.tfvars not found, using defaults"
        terraform plan -var="stack_name=$stack_name"
    else
        terraform plan -var="stack_name=$stack_name"
    fi
}

tf_apply() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_step "Deploying infrastructure for: $stack_name"
    cd "$SCRIPT_DIR/tf"

    if [ ! -d ".terraform" ]; then
        log_info "Running terraform init first..."
        terraform init
    fi

    terraform apply -var="stack_name=$stack_name" -auto-approve
    log_success "Infrastructure deployed"
}

tf_destroy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    confirm_action "This will destroy all infrastructure for: $stack_name"

    log_step "Destroying infrastructure for: $stack_name"
    cd "$SCRIPT_DIR/tf"
    terraform destroy -var="stack_name=$stack_name" -auto-approve
    log_success "Infrastructure destroyed"
}

tf_output() {
    cd "$SCRIPT_DIR/tf"
    terraform output
}

# =============================================================================
# Training Job Functions
# =============================================================================
training_create() {
    local name=$1
    local image=$2
    local s3_input=$3
    local s3_output=$4
    local role_arn=$5

    require_param "$name" "Training job name"
    require_param "$image" "Container image URI"
    require_param "$s3_input" "S3 input path"
    require_param "$s3_output" "S3 output path"

    if [ -z "$role_arn" ]; then
        local account_id=$(get_account_id)
        role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"
    fi

    log_step "Creating training job: $name"

    aws sagemaker create-training-job \
        --training-job-name "$name" \
        --algorithm-specification "{
            \"TrainingImage\": \"$image\",
            \"TrainingInputMode\": \"File\"
        }" \
        --role-arn "$role_arn" \
        --input-data-config "[{
            \"ChannelName\": \"training\",
            \"DataSource\": {
                \"S3DataSource\": {
                    \"S3DataType\": \"S3Prefix\",
                    \"S3Uri\": \"$s3_input\",
                    \"S3DataDistributionType\": \"FullyReplicated\"
                }
            }
        }]" \
        --output-data-config "{
            \"S3OutputPath\": \"$s3_output\"
        }" \
        --resource-config "{
            \"InstanceType\": \"$DEFAULT_INSTANCE_TYPE\",
            \"InstanceCount\": 1,
            \"VolumeSizeInGB\": $DEFAULT_VOLUME_SIZE
        }" \
        --stopping-condition "{\"MaxRuntimeInSeconds\": $DEFAULT_MAX_RUNTIME}"

    log_success "Training job created: $name"
    echo ""
    echo "Monitor with: $0 training-describe $name"
    echo "View logs with: $0 training-logs $name"
}

training_list() {
    local status_filter=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                status_filter="--status-equals $2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    log_step "Listing training jobs..."
    aws sagemaker list-training-jobs $status_filter \
        --query 'TrainingJobSummaries[*].{Name:TrainingJobName,Status:TrainingJobStatus,Created:CreationTime}' \
        --output table
}

training_describe() {
    local name=$1
    require_param "$name" "Training job name"

    log_step "Describing training job: $name"
    aws sagemaker describe-training-job \
        --training-job-name "$name" \
        --query '{Name:TrainingJobName,Status:TrainingJobStatus,SecondaryStatus:SecondaryStatus,FailureReason:FailureReason,ModelArtifacts:ModelArtifacts.S3ModelArtifacts,Created:CreationTime,Duration:TrainingTimeInSeconds}' \
        --output table
}

training_stop() {
    local name=$1
    require_param "$name" "Training job name"

    log_step "Stopping training job: $name"
    aws sagemaker stop-training-job --training-job-name "$name"
    log_success "Stop request sent for training job: $name"
}

training_logs() {
    local name=$1
    require_param "$name" "Training job name"

    log_step "Fetching logs for training job: $name"
    aws logs tail "/aws/sagemaker/TrainingJobs" \
        --log-stream-name-prefix "$name" \
        --follow
}

# =============================================================================
# Processing Job Functions
# =============================================================================
processing_create() {
    local name=$1
    local image=$2
    local s3_input=$3
    local s3_output=$4
    local role_arn=$5

    require_param "$name" "Processing job name"
    require_param "$image" "Container image URI"
    require_param "$s3_input" "S3 input path"
    require_param "$s3_output" "S3 output path"

    if [ -z "$role_arn" ]; then
        local account_id=$(get_account_id)
        role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"
    fi

    log_step "Creating processing job: $name"

    aws sagemaker create-processing-job \
        --processing-job-name "$name" \
        --processing-resources "{
            \"ClusterConfig\": {
                \"InstanceCount\": 1,
                \"InstanceType\": \"$DEFAULT_INSTANCE_TYPE\",
                \"VolumeSizeInGB\": $DEFAULT_VOLUME_SIZE
            }
        }" \
        --app-specification "{
            \"ImageUri\": \"$image\"
        }" \
        --role-arn "$role_arn" \
        --processing-inputs "[{
            \"InputName\": \"input\",
            \"S3Input\": {
                \"S3Uri\": \"$s3_input\",
                \"LocalPath\": \"/opt/ml/processing/input\",
                \"S3DataType\": \"S3Prefix\",
                \"S3InputMode\": \"File\"
            }
        }]" \
        --processing-output-config "{
            \"Outputs\": [{
                \"OutputName\": \"output\",
                \"S3Output\": {
                    \"S3Uri\": \"$s3_output\",
                    \"LocalPath\": \"/opt/ml/processing/output\",
                    \"S3UploadMode\": \"EndOfJob\"
                }
            }]
        }"

    log_success "Processing job created: $name"
}

processing_list() {
    local status_filter=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                status_filter="--status-equals $2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    log_step "Listing processing jobs..."
    aws sagemaker list-processing-jobs $status_filter \
        --query 'ProcessingJobSummaries[*].{Name:ProcessingJobName,Status:ProcessingJobStatus,Created:CreationTime}' \
        --output table
}

processing_describe() {
    local name=$1
    require_param "$name" "Processing job name"

    log_step "Describing processing job: $name"
    aws sagemaker describe-processing-job \
        --processing-job-name "$name" \
        --query '{Name:ProcessingJobName,Status:ProcessingJobStatus,FailureReason:FailureReason,Created:CreationTime,Duration:ProcessingEndTime}' \
        --output table
}

processing_stop() {
    local name=$1
    require_param "$name" "Processing job name"

    log_step "Stopping processing job: $name"
    aws sagemaker stop-processing-job --processing-job-name "$name"
    log_success "Stop request sent for processing job: $name"
}

# =============================================================================
# Notebook Instance Functions
# =============================================================================
notebook_create() {
    local name=$1
    local role_arn=$2

    require_param "$name" "Notebook instance name"

    if [ -z "$role_arn" ]; then
        local account_id=$(get_account_id)
        role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"
    fi

    log_step "Creating notebook instance: $name"

    aws sagemaker create-notebook-instance \
        --notebook-instance-name "$name" \
        --instance-type "$DEFAULT_NOTEBOOK_INSTANCE_TYPE" \
        --role-arn "$role_arn" \
        --volume-size-in-gb 20

    log_info "Notebook instance created. Waiting for InService status..."
    aws sagemaker wait notebook-instance-in-service \
        --notebook-instance-name "$name"

    log_success "Notebook instance is ready: $name"
    echo ""
    echo "Get URL with: $0 notebook-url $name"
}

notebook_list() {
    log_step "Listing notebook instances..."
    aws sagemaker list-notebook-instances \
        --query 'NotebookInstances[*].{Name:NotebookInstanceName,Status:NotebookInstanceStatus,Type:InstanceType,Created:CreationTime}' \
        --output table
}

notebook_describe() {
    local name=$1
    require_param "$name" "Notebook instance name"

    log_step "Describing notebook instance: $name"
    aws sagemaker describe-notebook-instance \
        --notebook-instance-name "$name" \
        --query '{Name:NotebookInstanceName,Status:NotebookInstanceStatus,Type:InstanceType,Url:Url,Created:CreationTime}' \
        --output table
}

notebook_start() {
    local name=$1
    require_param "$name" "Notebook instance name"

    log_step "Starting notebook instance: $name"
    aws sagemaker start-notebook-instance --notebook-instance-name "$name"

    log_info "Waiting for notebook to start..."
    aws sagemaker wait notebook-instance-in-service \
        --notebook-instance-name "$name"

    log_success "Notebook instance started: $name"
}

notebook_stop() {
    local name=$1
    require_param "$name" "Notebook instance name"

    log_step "Stopping notebook instance: $name"
    aws sagemaker stop-notebook-instance --notebook-instance-name "$name"

    log_info "Waiting for notebook to stop..."
    aws sagemaker wait notebook-instance-stopped \
        --notebook-instance-name "$name"

    log_success "Notebook instance stopped: $name"
}

notebook_delete() {
    local name=$1
    require_param "$name" "Notebook instance name"

    confirm_action "This will delete notebook instance: $name"

    # Check status and stop if running
    local status=$(aws sagemaker describe-notebook-instance \
        --notebook-instance-name "$name" \
        --query 'NotebookInstanceStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [ "$status" = "InService" ]; then
        log_step "Stopping notebook first..."
        aws sagemaker stop-notebook-instance --notebook-instance-name "$name"
        aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$name"
    fi

    log_step "Deleting notebook instance: $name"
    aws sagemaker delete-notebook-instance --notebook-instance-name "$name"
    log_success "Notebook instance deleted: $name"
}

notebook_url() {
    local name=$1
    require_param "$name" "Notebook instance name"

    log_step "Getting presigned URL for notebook: $name"
    local url=$(aws sagemaker create-presigned-notebook-instance-url \
        --notebook-instance-name "$name" \
        --query 'AuthorizedUrl' \
        --output text)

    echo ""
    echo -e "${GREEN}Notebook URL:${NC}"
    echo "$url"
}

# =============================================================================
# Model Functions
# =============================================================================
model_create() {
    local name=$1
    local image=$2
    local model_s3_uri=$3
    local role_arn=$4

    require_param "$name" "Model name"
    require_param "$image" "Container image URI"
    require_param "$model_s3_uri" "Model S3 URI"

    if [ -z "$role_arn" ]; then
        local account_id=$(get_account_id)
        role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"
    fi

    log_step "Creating model: $name"

    aws sagemaker create-model \
        --model-name "$name" \
        --primary-container "{
            \"Image\": \"$image\",
            \"ModelDataUrl\": \"$model_s3_uri\"
        }" \
        --execution-role-arn "$role_arn"

    log_success "Model created: $name"
}

model_list() {
    log_step "Listing models..."
    aws sagemaker list-models \
        --query 'Models[*].{Name:ModelName,Created:CreationTime}' \
        --output table
}

model_describe() {
    local name=$1
    require_param "$name" "Model name"

    log_step "Describing model: $name"
    aws sagemaker describe-model \
        --model-name "$name" \
        --output yaml
}

model_delete() {
    local name=$1
    require_param "$name" "Model name"

    confirm_action "This will delete model: $name"

    log_step "Deleting model: $name"
    aws sagemaker delete-model --model-name "$name"
    log_success "Model deleted: $name"
}

# =============================================================================
# Endpoint Configuration Functions
# =============================================================================
endpoint_config_create() {
    local name=$1
    local model_name=$2
    local instance_type=${3:-$DEFAULT_INSTANCE_TYPE}
    local instance_count=${4:-1}

    require_param "$name" "Endpoint config name"
    require_param "$model_name" "Model name"

    log_step "Creating endpoint configuration: $name"

    aws sagemaker create-endpoint-config \
        --endpoint-config-name "$name" \
        --production-variants "[{
            \"VariantName\": \"default\",
            \"ModelName\": \"$model_name\",
            \"InstanceType\": \"$instance_type\",
            \"InitialInstanceCount\": $instance_count
        }]"

    log_success "Endpoint configuration created: $name"
}

endpoint_config_list() {
    log_step "Listing endpoint configurations..."
    aws sagemaker list-endpoint-configs \
        --query 'EndpointConfigs[*].{Name:EndpointConfigName,Created:CreationTime}' \
        --output table
}

endpoint_config_delete() {
    local name=$1
    require_param "$name" "Endpoint config name"

    confirm_action "This will delete endpoint configuration: $name"

    log_step "Deleting endpoint configuration: $name"
    aws sagemaker delete-endpoint-config --endpoint-config-name "$name"
    log_success "Endpoint configuration deleted: $name"
}

# =============================================================================
# Endpoint Functions
# =============================================================================
endpoint_create() {
    local name=$1
    local config_name=$2

    require_param "$name" "Endpoint name"
    require_param "$config_name" "Endpoint configuration name"

    log_step "Creating endpoint: $name"

    aws sagemaker create-endpoint \
        --endpoint-name "$name" \
        --endpoint-config-name "$config_name"

    log_info "Endpoint creation started. Waiting for InService status..."
    log_warn "This may take 5-10 minutes..."

    aws sagemaker wait endpoint-in-service --endpoint-name "$name"
    log_success "Endpoint is ready: $name"
}

endpoint_list() {
    log_step "Listing endpoints..."
    aws sagemaker list-endpoints \
        --query 'Endpoints[*].{Name:EndpointName,Status:EndpointStatus,Created:CreationTime}' \
        --output table
}

endpoint_describe() {
    local name=$1
    require_param "$name" "Endpoint name"

    log_step "Describing endpoint: $name"
    aws sagemaker describe-endpoint \
        --endpoint-name "$name" \
        --query '{Name:EndpointName,Status:EndpointStatus,Config:EndpointConfigName,Created:CreationTime,LastModified:LastModifiedTime}' \
        --output table
}

endpoint_update() {
    local name=$1
    local config_name=$2

    require_param "$name" "Endpoint name"
    require_param "$config_name" "Endpoint configuration name"

    log_step "Updating endpoint: $name"

    aws sagemaker update-endpoint \
        --endpoint-name "$name" \
        --endpoint-config-name "$config_name"

    log_info "Endpoint update started. Waiting for completion..."
    aws sagemaker wait endpoint-in-service --endpoint-name "$name"
    log_success "Endpoint updated: $name"
}

endpoint_delete() {
    local name=$1
    require_param "$name" "Endpoint name"

    confirm_action "This will delete endpoint: $name"

    log_step "Deleting endpoint: $name"
    aws sagemaker delete-endpoint --endpoint-name "$name"
    log_success "Endpoint deleted: $name"
}

endpoint_invoke() {
    local name=$1
    local payload=$2

    require_param "$name" "Endpoint name"
    require_param "$payload" "Payload (JSON string or @file)"

    log_step "Invoking endpoint: $name"

    if [[ "$payload" == @* ]]; then
        # File path
        aws sagemaker-runtime invoke-endpoint \
            --endpoint-name "$name" \
            --content-type "application/json" \
            --body "file://${payload:1}" \
            /dev/stdout
    else
        # JSON string
        aws sagemaker-runtime invoke-endpoint \
            --endpoint-name "$name" \
            --content-type "application/json" \
            --body "$payload" \
            /dev/stdout
    fi
}

# =============================================================================
# Experiment Functions
# =============================================================================
experiment_create() {
    local name=$1
    local description=${2:-"ML experiment: $name"}

    require_param "$name" "Experiment name"

    log_step "Creating experiment: $name"

    aws sagemaker create-experiment \
        --experiment-name "$name" \
        --description "$description"

    log_success "Experiment created: $name"
}

experiment_list() {
    log_step "Listing experiments..."
    aws sagemaker list-experiments \
        --query 'ExperimentSummaries[*].{Name:ExperimentName,Created:CreationTime}' \
        --output table
}

experiment_describe() {
    local name=$1
    require_param "$name" "Experiment name"

    log_step "Describing experiment: $name"
    aws sagemaker describe-experiment \
        --experiment-name "$name" \
        --output yaml
}

experiment_delete() {
    local name=$1
    require_param "$name" "Experiment name"

    confirm_action "This will delete experiment: $name"

    log_step "Deleting experiment: $name"
    aws sagemaker delete-experiment --experiment-name "$name"
    log_success "Experiment deleted: $name"
}

trial_create() {
    local name=$1
    local experiment=$2

    require_param "$name" "Trial name"
    require_param "$experiment" "Experiment name"

    log_step "Creating trial: $name"

    aws sagemaker create-trial \
        --trial-name "$name" \
        --experiment-name "$experiment"

    log_success "Trial created: $name"
}

trial_list() {
    local experiment=$1
    require_param "$experiment" "Experiment name"

    log_step "Listing trials in experiment: $experiment"
    aws sagemaker list-trials \
        --experiment-name "$experiment" \
        --query 'TrialSummaries[*].{Name:TrialName,Created:CreationTime}' \
        --output table
}

trial_delete() {
    local name=$1
    require_param "$name" "Trial name"

    confirm_action "This will delete trial: $name"

    log_step "Deleting trial: $name"
    aws sagemaker delete-trial --trial-name "$name"
    log_success "Trial deleted: $name"
}

# =============================================================================
# Model Registry Functions
# =============================================================================
model_package_group_create() {
    local name=$1
    require_param "$name" "Model package group name"

    log_step "Creating model package group: $name"

    aws sagemaker create-model-package-group \
        --model-package-group-name "$name" \
        --model-package-group-description "Model package group: $name"

    log_success "Model package group created: $name"
}

model_package_group_list() {
    log_step "Listing model package groups..."
    aws sagemaker list-model-package-groups \
        --query 'ModelPackageGroupSummaryList[*].{Name:ModelPackageGroupName,Status:ModelPackageGroupStatus,Created:CreationTime}' \
        --output table
}

model_package_group_delete() {
    local name=$1
    require_param "$name" "Model package group name"

    confirm_action "This will delete model package group: $name"

    log_step "Deleting model package group: $name"
    aws sagemaker delete-model-package-group --model-package-group-name "$name"
    log_success "Model package group deleted: $name"
}

model_package_list() {
    local group=$1
    require_param "$group" "Model package group name"

    log_step "Listing model packages in group: $group"
    aws sagemaker list-model-packages \
        --model-package-group-name "$group" \
        --query 'ModelPackageSummaryList[*].{Name:ModelPackageName,Status:ModelPackageStatus,Version:ModelPackageVersion}' \
        --output table
}

# =============================================================================
# IAM Role Functions
# =============================================================================
role_create() {
    local name=${1:-sagemaker-execution-role}

    log_step "Creating SageMaker execution role: $name"

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "sagemaker.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "$name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    # Attach policies
    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess" 2>/dev/null || true

    sleep 10

    local account_id=$(get_account_id)
    log_success "Role created: arn:aws:iam::${account_id}:role/$name"
}

role_delete() {
    local name=${1:-sagemaker-execution-role}

    confirm_action "This will delete IAM role: $name"

    log_step "Deleting SageMaker execution role: $name"
    delete_role_with_policies "$name"
    log_success "Role deleted: $name"
}

role_list() {
    log_step "Listing SageMaker-related roles..."
    aws iam list-roles \
        --query "Roles[?contains(RoleName, 'sagemaker') || contains(RoleName, 'SageMaker')].{Name:RoleName,Created:CreateDate}" \
        --output table
}

# =============================================================================
# Utility Functions
# =============================================================================
status() {
    log_info "=== SageMaker Resource Status ==="
    echo ""

    echo -e "${BLUE}=== Training Jobs ===${NC}"
    aws sagemaker list-training-jobs \
        --max-results 10 \
        --query 'TrainingJobSummaries[*].{Name:TrainingJobName,Status:TrainingJobStatus}' \
        --output table 2>/dev/null || echo "No training jobs found"
    echo ""

    echo -e "${BLUE}=== Processing Jobs ===${NC}"
    aws sagemaker list-processing-jobs \
        --max-results 10 \
        --query 'ProcessingJobSummaries[*].{Name:ProcessingJobName,Status:ProcessingJobStatus}' \
        --output table 2>/dev/null || echo "No processing jobs found"
    echo ""

    echo -e "${BLUE}=== Notebook Instances ===${NC}"
    aws sagemaker list-notebook-instances \
        --query 'NotebookInstances[*].{Name:NotebookInstanceName,Status:NotebookInstanceStatus,Type:InstanceType}' \
        --output table 2>/dev/null || echo "No notebook instances found"
    echo ""

    echo -e "${BLUE}=== Models ===${NC}"
    aws sagemaker list-models \
        --max-results 10 \
        --query 'Models[*].{Name:ModelName,Created:CreationTime}' \
        --output table 2>/dev/null || echo "No models found"
    echo ""

    echo -e "${BLUE}=== Endpoints ===${NC}"
    aws sagemaker list-endpoints \
        --query 'Endpoints[*].{Name:EndpointName,Status:EndpointStatus}' \
        --output table 2>/dev/null || echo "No endpoints found"
    echo ""

    echo -e "${BLUE}=== Experiments ===${NC}"
    aws sagemaker list-experiments \
        --max-results 10 \
        --query 'ExperimentSummaries[*].{Name:ExperimentName}' \
        --output table 2>/dev/null || echo "No experiments found"
}

show_images() {
    local framework=${1:-}
    local region=$(get_region)

    echo -e "${BLUE}=== Available SageMaker Deep Learning Container Images ===${NC}"
    echo ""
    echo "Region: $region"
    echo ""

    if [ -z "$framework" ]; then
        echo "PyTorch Training:"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-training:2.0-cpu-py310"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-training:2.0-gpu-py310"
        echo ""
        echo "PyTorch Inference:"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-inference:2.0-cpu-py310"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-inference:2.0-gpu-py310"
        echo ""
        echo "TensorFlow Training:"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-training:2.13-cpu-py310"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-training:2.13-gpu-py310"
        echo ""
        echo "TensorFlow Inference:"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-inference:2.13-cpu"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-inference:2.13-gpu"
        echo ""
        echo "Scikit-learn:"
        echo "  683313688378.dkr.ecr.${region}.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
        echo ""
        echo "XGBoost:"
        echo "  683313688378.dkr.ecr.${region}.amazonaws.com/sagemaker-xgboost:1.7-1"
        echo ""
        echo "HuggingFace:"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-cpu-py310"
        echo "  763104351884.dkr.ecr.${region}.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-gpu-py310"
        echo ""
        echo "For more images, visit:"
        echo "  https://github.com/aws/deep-learning-containers/blob/master/available_images.md"
    else
        case $framework in
            pytorch)
                echo "PyTorch images:"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-training:2.0-cpu-py310"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-training:2.0-gpu-py310"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-inference:2.0-cpu-py310"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/pytorch-inference:2.0-gpu-py310"
                ;;
            tensorflow)
                echo "TensorFlow images:"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-training:2.13-cpu-py310"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-training:2.13-gpu-py310"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-inference:2.13-cpu"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/tensorflow-inference:2.13-gpu"
                ;;
            sklearn|scikit-learn)
                echo "Scikit-learn images:"
                echo "  683313688378.dkr.ecr.${region}.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
                ;;
            xgboost)
                echo "XGBoost images:"
                echo "  683313688378.dkr.ecr.${region}.amazonaws.com/sagemaker-xgboost:1.7-1"
                ;;
            huggingface)
                echo "HuggingFace images:"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-cpu-py310"
                echo "  763104351884.dkr.ecr.${region}.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-gpu-py310"
                ;;
            *)
                echo "Unknown framework: $framework"
                echo "Supported: pytorch, tensorflow, sklearn, xgboost, huggingface"
                ;;
        esac
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
    # Terraform
    tf-init)
        tf_init
        ;;
    tf-plan)
        tf_plan "$@"
        ;;
    tf-apply)
        tf_apply "$@"
        ;;
    tf-destroy)
        tf_destroy "$@"
        ;;
    tf-output)
        tf_output
        ;;

    # Training Jobs
    training-create)
        training_create "$@"
        ;;
    training-list)
        training_list "$@"
        ;;
    training-describe)
        training_describe "$@"
        ;;
    training-stop)
        training_stop "$@"
        ;;
    training-logs)
        training_logs "$@"
        ;;

    # Processing Jobs
    processing-create)
        processing_create "$@"
        ;;
    processing-list)
        processing_list "$@"
        ;;
    processing-describe)
        processing_describe "$@"
        ;;
    processing-stop)
        processing_stop "$@"
        ;;

    # Notebook Instances
    notebook-create)
        notebook_create "$@"
        ;;
    notebook-list)
        notebook_list
        ;;
    notebook-describe)
        notebook_describe "$@"
        ;;
    notebook-start)
        notebook_start "$@"
        ;;
    notebook-stop)
        notebook_stop "$@"
        ;;
    notebook-delete)
        notebook_delete "$@"
        ;;
    notebook-url)
        notebook_url "$@"
        ;;

    # Models
    model-create)
        model_create "$@"
        ;;
    model-list)
        model_list
        ;;
    model-describe)
        model_describe "$@"
        ;;
    model-delete)
        model_delete "$@"
        ;;

    # Endpoint Configurations
    endpoint-config-create)
        endpoint_config_create "$@"
        ;;
    endpoint-config-list)
        endpoint_config_list
        ;;
    endpoint-config-delete)
        endpoint_config_delete "$@"
        ;;

    # Endpoints
    endpoint-create)
        endpoint_create "$@"
        ;;
    endpoint-list)
        endpoint_list
        ;;
    endpoint-describe)
        endpoint_describe "$@"
        ;;
    endpoint-update)
        endpoint_update "$@"
        ;;
    endpoint-delete)
        endpoint_delete "$@"
        ;;
    endpoint-invoke)
        endpoint_invoke "$@"
        ;;

    # Experiments
    experiment-create)
        experiment_create "$@"
        ;;
    experiment-list)
        experiment_list
        ;;
    experiment-describe)
        experiment_describe "$@"
        ;;
    experiment-delete)
        experiment_delete "$@"
        ;;
    trial-create)
        trial_create "$@"
        ;;
    trial-list)
        trial_list "$@"
        ;;
    trial-delete)
        trial_delete "$@"
        ;;

    # Model Registry
    model-package-group-create)
        model_package_group_create "$@"
        ;;
    model-package-group-list)
        model_package_group_list
        ;;
    model-package-group-delete)
        model_package_group_delete "$@"
        ;;
    model-package-list)
        model_package_list "$@"
        ;;

    # IAM Roles
    role-create)
        role_create "$@"
        ;;
    role-delete)
        role_delete "$@"
        ;;
    role-list)
        role_list
        ;;

    # Utilities
    status)
        status
        ;;
    images)
        show_images "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
