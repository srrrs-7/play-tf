#!/bin/bash
# =============================================================================
# Lambda (Container Image) + ECR Architecture Script
# =============================================================================
# This script creates and manages the following architecture:
#   - ECR repository for Lambda container images
#   - Lambda function using container image from ECR
#   - IAM role with ECR pull permissions
#   - CloudWatch Log Group
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
DEFAULT_LAMBDA_TIMEOUT=30
DEFAULT_LAMBDA_MEMORY=512

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Lambda (Container Image) + ECR Architecture"
    echo ""
    echo "  ECR Repository -> Lambda Container Image Function"
    echo ""
    echo "Commands:"
    echo ""
    echo "  === Full Stack ==="
    echo "  deploy <stack-name>                    - Deploy the full architecture"
    echo "  destroy <stack-name>                   - Destroy all resources"
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
    echo "  === Docker Build ==="
    echo "  build <stack-name>                     - Build Docker image from src/"
    echo "  build-push <stack-name>                - Build and push to ECR"
    echo ""
    echo "  === Lambda ==="
    echo "  lambda-create <name> <image-uri>       - Create Lambda from container image"
    echo "  lambda-list                            - List Lambda functions"
    echo "  lambda-delete <name>                   - Delete Lambda function"
    echo "  lambda-invoke <name> [payload]         - Invoke Lambda function"
    echo "  lambda-update <name> <image-uri>       - Update Lambda image"
    echo "  lambda-logs <name>                     - View Lambda logs"
    echo ""
    echo "  === IAM ==="
    echo "  iam-create-role <name>                 - Create Lambda execution role"
    echo "  iam-delete-role <name>                 - Delete Lambda execution role"
    echo ""
    echo "Examples:"
    echo "  # Deploy full stack (creates ECR repo, builds image, deploys Lambda)"
    echo "  $0 deploy my-lambda"
    echo ""
    echo "  # Manual step-by-step deployment"
    echo "  $0 ecr-create my-lambda"
    echo "  $0 build my-lambda"
    echo "  $0 ecr-login"
    echo "  $0 ecr-push my-lambda my-lambda:latest"
    echo "  $0 lambda-create my-lambda <account>.dkr.ecr.<region>.amazonaws.com/my-lambda:latest"
    echo ""
    echo "  # Invoke function"
    echo "  $0 lambda-invoke my-lambda '{\"key\": \"value\"}'"
    echo ""
    echo "  # Update Lambda with new image"
    echo "  $0 build-push my-lambda"
    echo "  $0 lambda-update my-lambda <image-uri>"
    echo ""
    exit 1
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
# Docker Build Functions
# =============================================================================
build_image() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_step "Building Docker image: $stack_name"

    local src_dir="$SCRIPT_DIR/src"
    if [ ! -d "$src_dir" ]; then
        log_error "Source directory not found: $src_dir"
        exit 1
    fi

    if [ ! -f "$src_dir/Dockerfile" ]; then
        log_error "Dockerfile not found: $src_dir/Dockerfile"
        exit 1
    fi

    cd "$src_dir"
    docker build --platform linux/amd64 -t "$stack_name:latest" .
    cd - > /dev/null

    log_success "Built image: $stack_name:latest"
}

build_and_push() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    build_image "$stack_name"
    ecr_login
    ecr_push "$stack_name" "$stack_name:latest"
}

# =============================================================================
# IAM Functions
# =============================================================================
iam_create_role() {
    local role_name=$1
    require_param "$role_name" "Role name"

    log_step "Creating Lambda execution role: $role_name"

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || {
        log_info "Role $role_name already exists"
        return 0
    }

    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Attach ECR read-only policy for pulling images
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10

    log_success "Created Lambda execution role: $role_name"
}

iam_delete_role() {
    local role_name=$1
    require_param "$role_name" "Role name"

    confirm_action "This will delete IAM role '$role_name'"

    log_step "Deleting Lambda execution role: $role_name"
    delete_role_with_policies "$role_name"
    log_success "Deleted role: $role_name"
}

# =============================================================================
# Lambda Functions
# =============================================================================
lambda_create() {
    local name=$1
    local image_uri=$2
    require_param "$name" "Function name"
    require_param "$image_uri" "Image URI"

    log_step "Creating Lambda function: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-lambda-role"

    # Ensure role exists
    iam_create_role "$role_name"

    local role_arn="arn:aws:iam::$account_id:role/$role_name"

    aws lambda create-function \
        --function-name "$name" \
        --package-type Image \
        --code ImageUri="$image_uri" \
        --role "$role_arn" \
        --timeout "$DEFAULT_LAMBDA_TIMEOUT" \
        --memory-size "$DEFAULT_LAMBDA_MEMORY" \
        --architectures x86_64 \
        --query '{FunctionName:FunctionName,State:State,CodeSize:CodeSize,Runtime:PackageType,MemorySize:MemorySize}' \
        --output table

    log_success "Created Lambda function: $name"
}

lambda_list() {
    log_step "Listing Lambda functions..."
    aws lambda list-functions \
        --query 'Functions[*].{Name:FunctionName,Runtime:Runtime,PackageType:PackageType,Memory:MemorySize,Timeout:Timeout}' \
        --output table
}

lambda_delete() {
    local name=$1
    require_param "$name" "Function name"

    confirm_action "This will delete Lambda function '$name'"

    log_step "Deleting Lambda function: $name"
    aws lambda delete-function --function-name "$name"
    log_success "Deleted Lambda function: $name"
}

lambda_invoke() {
    local name=$1
    local payload=${2:-'{}'}
    require_param "$name" "Function name"

    log_step "Invoking Lambda function: $name"

    local output_file="/tmp/lambda-response-$(date +%s).json"

    aws lambda invoke \
        --function-name "$name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        "$output_file"

    echo ""
    echo -e "${GREEN}Response:${NC}"
    cat "$output_file"
    echo ""
    rm -f "$output_file"
}

lambda_update() {
    local name=$1
    local image_uri=$2
    require_param "$name" "Function name"
    require_param "$image_uri" "Image URI"

    log_step "Updating Lambda function: $name"

    aws lambda update-function-code \
        --function-name "$name" \
        --image-uri "$image_uri" \
        --query '{FunctionName:FunctionName,State:State,LastModified:LastModified}' \
        --output table

    log_success "Updated Lambda function: $name"
}

lambda_logs() {
    local name=$1
    require_param "$name" "Function name"

    log_step "Fetching logs for: $name"

    local log_group="/aws/lambda/$name"

    # Get latest log streams
    local stream=$(aws logs describe-log-streams \
        --log-group-name "$log_group" \
        --order-by LastEventTime \
        --descending \
        --limit 1 \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null)

    if [ -z "$stream" ] || [ "$stream" = "None" ]; then
        log_warn "No logs found for function: $name"
        return
    fi

    echo -e "${BLUE}Log stream: $stream${NC}"
    echo ""

    aws logs get-log-events \
        --log-group-name "$log_group" \
        --log-stream-name "$stream" \
        --limit 50 \
        --query 'events[*].message' \
        --output text
}

# =============================================================================
# Full Stack Operations
# =============================================================================
deploy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_info "Deploying Lambda + ECR architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - ECR repository for Lambda container images"
    echo "  - Docker image built from src/"
    echo "  - Lambda function using container image"
    echo "  - IAM execution role"
    echo ""

    local src_dir="$SCRIPT_DIR/src"
    if [ ! -d "$src_dir" ] || [ ! -f "$src_dir/Dockerfile" ]; then
        log_error "Source directory with Dockerfile required at: $src_dir"
        echo ""
        echo "Please ensure the following files exist:"
        echo "  - $src_dir/Dockerfile"
        echo "  - $src_dir/index.ts (or other handler)"
        exit 1
    fi

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""

    log_step "Step 1/4: Creating IAM role..."
    iam_create_role "${stack_name}-lambda-role"
    echo ""

    log_step "Step 2/4: Creating ECR repository..."
    ecr_create "$stack_name" 2>/dev/null || log_info "ECR repository may already exist"
    echo ""

    log_step "Step 3/4: Building and pushing Docker image..."
    build_and_push "$stack_name"
    echo ""

    log_step "Step 4/4: Creating Lambda function..."
    local account_id=$(get_account_id)
    local region=$(get_region)
    local image_uri="$account_id.dkr.ecr.$region.amazonaws.com/$stack_name:latest"

    lambda_create "$stack_name" "$image_uri"
    echo ""

    log_success "Deployment complete!"
    echo ""
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo "Stack Name:       $stack_name"
    echo "ECR Repository:   $account_id.dkr.ecr.$region.amazonaws.com/$stack_name"
    echo "Lambda Function:  $stack_name"
    echo ""
    echo -e "${YELLOW}=== Usage ===${NC}"
    echo "Invoke function:"
    echo "  $0 lambda-invoke $stack_name '{\"key\": \"value\"}'"
    echo ""
    echo "View logs:"
    echo "  $0 lambda-logs $stack_name"
    echo ""
    echo "Update function (after image changes):"
    echo "  $0 build-push $stack_name"
    echo "  $0 lambda-update $stack_name $image_uri"
}

destroy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_warn "This will destroy all resources for: $stack_name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Lambda function"
    echo "  - IAM execution role"
    echo "  - ECR repository (and all images)"
    echo "  - CloudWatch log group"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""

    # Delete Lambda function
    log_step "Deleting Lambda function..."
    aws lambda delete-function --function-name "$stack_name" 2>/dev/null || true
    log_info "Deleted Lambda function: $stack_name"

    # Delete IAM role
    log_step "Deleting IAM role..."
    delete_role_with_policies "${stack_name}-lambda-role" 2>/dev/null || true
    log_info "Deleted IAM role: ${stack_name}-lambda-role"

    # Delete ECR repository
    log_step "Deleting ECR repository..."
    aws ecr delete-repository --repository-name "$stack_name" --force 2>/dev/null || true
    log_info "Deleted ECR repository: $stack_name"

    # Delete CloudWatch log group
    log_step "Deleting CloudWatch log group..."
    aws logs delete-log-group --log-group-name "/aws/lambda/$stack_name" 2>/dev/null || true
    log_info "Deleted log group: /aws/lambda/$stack_name"

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
            --query 'repositories[*].{Name:repositoryName,URI:repositoryUri,CreatedAt:createdAt}' \
            --output table 2>/dev/null || echo "No ECR repository found"

        echo -e "\n${BLUE}=== ECR Images ===${NC}"
        aws ecr describe-images \
            --repository-name "$stack_name" \
            --query 'imageDetails[*].{Tags:imageTags[0],Size:imageSizeInBytes,PushedAt:imagePushedAt}' \
            --output table 2>/dev/null || echo "No images found"
    else
        ecr_list
    fi

    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    if [ -n "$stack_name" ]; then
        aws lambda get-function \
            --function-name "$stack_name" \
            --query '{Name:Configuration.FunctionName,State:Configuration.State,Memory:Configuration.MemorySize,Timeout:Configuration.Timeout,PackageType:Configuration.PackageType,LastModified:Configuration.LastModified}' \
            --output table 2>/dev/null || echo "No Lambda function found"
    else
        lambda_list
    fi

    echo -e "\n${BLUE}=== IAM Roles ===${NC}"
    if [ -n "$stack_name" ]; then
        aws iam get-role \
            --role-name "${stack_name}-lambda-role" \
            --query 'Role.{RoleName:RoleName,CreateDate:CreateDate,Arn:Arn}' \
            --output table 2>/dev/null || echo "No IAM role found"
    else
        aws iam list-roles \
            --query 'Roles[?contains(RoleName, `lambda`)].{RoleName:RoleName,CreateDate:CreateDate}' \
            --output table
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

    # Docker Build
    build)
        build_image "$@"
        ;;
    build-push)
        build_and_push "$@"
        ;;

    # Lambda
    lambda-create)
        lambda_create "$@"
        ;;
    lambda-list)
        lambda_list
        ;;
    lambda-delete)
        lambda_delete "$@"
        ;;
    lambda-invoke)
        lambda_invoke "$@"
        ;;
    lambda-update)
        lambda_update "$@"
        ;;
    lambda-logs)
        lambda_logs "$@"
        ;;

    # IAM
    iam-create-role)
        iam_create_role "$@"
        ;;
    iam-delete-role)
        iam_delete_role "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
