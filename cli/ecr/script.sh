#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ECR Operations Script
# Provides common ECR (Elastic Container Registry) operations using AWS CLI

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list-repositories                   - List all ECR repositories"
    echo "  create-repository <name>            - Create a new ECR repository"
    echo "  delete-repository <name>            - Delete an ECR repository"
    echo "  describe-repository <name>          - Get repository details"
    echo "  get-login                           - Get Docker login command for ECR"
    echo "  docker-login                        - Authenticate Docker to ECR"
    echo "  list-images <repository-name>       - List images in a repository"
    echo "  describe-images <repository-name> [image-tag] - Get image details"
    echo "  tag-image <repository-name> <source-tag> <new-tag> - Tag an image"
    echo "  delete-image <repository-name> <image-tag> - Delete an image"
    echo "  push-image <repository-name> <local-image> [tag] - Push image to ECR"
    echo "  pull-image <repository-name> <image-tag> - Pull image from ECR"
    echo "  get-repository-uri <repository-name> - Get repository URI"
    echo "  set-lifecycle-policy <repository-name> <policy-file> - Set lifecycle policy"
    echo "  get-lifecycle-policy <repository-name> - Get lifecycle policy"
    echo "  set-repository-policy <repository-name> <policy-file> - Set repository policy"
    echo "  get-repository-policy <repository-name> - Get repository policy"
    echo "  scan-image <repository-name> <image-tag> - Scan image for vulnerabilities"
    echo "  get-scan-findings <repository-name> <image-tag> - Get scan results"
    echo ""
    exit 1
}

# List all ECR repositories
list_repositories() {
    echo -e "${GREEN}Listing all ECR repositories...${NC}"
    aws ecr describe-repositories --query 'repositories[*].[repositoryName,repositoryUri,createdAt]' --output table
}

# Create a new ECR repository
create_repository() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating ECR repository: $repo_name${NC}"
    aws ecr create-repository \
        --repository-name "$repo_name" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256

    echo -e "${GREEN}Repository created successfully${NC}"

    # Get and display repository URI
    local repo_uri=$(aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --query 'repositories[0].repositoryUri' \
        --output text)
    echo -e "${BLUE}Repository URI: $repo_uri${NC}"
}

# Delete an ECR repository
delete_repository() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete repository: $repo_name and all its images${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting ECR repository: $repo_name${NC}"
    aws ecr delete-repository --repository-name "$repo_name" --force
    echo -e "${GREEN}Repository deleted successfully${NC}"
}

# Describe repository
describe_repository() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for repository: $repo_name${NC}"
    aws ecr describe-repositories --repository-names "$repo_name"
}

# Get Docker login command
get_login() {
    echo -e "${GREEN}Getting Docker login command...${NC}"
    local region=${AWS_DEFAULT_REGION:-ap-northeast-1}
    aws ecr get-login-password --region "$region"
}

# Authenticate Docker to ECR
docker_login() {
    echo -e "${GREEN}Authenticating Docker to ECR...${NC}"
    local region=${AWS_DEFAULT_REGION:-ap-northeast-1}
    local account_id=$(aws sts get-caller-identity --query Account --output text)

    aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$account_id.dkr.ecr.$region.amazonaws.com"

    echo -e "${GREEN}Docker authentication successful${NC}"
}

# List images in a repository
list_images() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing images in repository: $repo_name${NC}"
    aws ecr list-images \
        --repository-name "$repo_name" \
        --query 'imageIds[*].[imageTag,imageDigest]' \
        --output table
}

# Describe images
describe_images() {
    local repo_name=$1
    local image_tag=$2

    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting image details for repository: $repo_name${NC}"

    if [ -n "$image_tag" ]; then
        aws ecr describe-images \
            --repository-name "$repo_name" \
            --image-ids imageTag="$image_tag"
    else
        aws ecr describe-images \
            --repository-name "$repo_name" \
            --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imageSizeInBytes,imagePushedAt]' \
            --output table
    fi
}

# Tag an image
tag_image() {
    local repo_name=$1
    local source_tag=$2
    local new_tag=$3

    if [ -z "$repo_name" ] || [ -z "$source_tag" ] || [ -z "$new_tag" ]; then
        echo -e "${RED}Error: Repository name, source tag, and new tag are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Tagging image in repository: $repo_name${NC}"

    # Get repository URI
    local repo_uri=$(aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --query 'repositories[0].repositoryUri' \
        --output text)

    # Get manifest for source image
    local manifest=$(aws ecr batch-get-image \
        --repository-name "$repo_name" \
        --image-ids imageTag="$source_tag" \
        --query 'images[0].imageManifest' \
        --output text)

    # Put image with new tag
    aws ecr put-image \
        --repository-name "$repo_name" \
        --image-tag "$new_tag" \
        --image-manifest "$manifest"

    echo -e "${GREEN}Image tagged successfully: $source_tag -> $new_tag${NC}"
}

# Delete an image
delete_image() {
    local repo_name=$1
    local image_tag=$2

    if [ -z "$repo_name" ] || [ -z "$image_tag" ]; then
        echo -e "${RED}Error: Repository name and image tag are required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete image: $repo_name:$image_tag${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting image: $repo_name:$image_tag${NC}"
    aws ecr batch-delete-image \
        --repository-name "$repo_name" \
        --image-ids imageTag="$image_tag"
    echo -e "${GREEN}Image deleted successfully${NC}"
}

# Push image to ECR
push_image() {
    local repo_name=$1
    local local_image=$2
    local tag=${3:-latest}

    if [ -z "$repo_name" ] || [ -z "$local_image" ]; then
        echo -e "${RED}Error: Repository name and local image are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Pushing image to ECR repository: $repo_name${NC}"

    # Get repository URI
    local repo_uri=$(aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --query 'repositories[0].repositoryUri' \
        --output text)

    if [ -z "$repo_uri" ]; then
        echo -e "${RED}Error: Repository not found: $repo_name${NC}"
        exit 1
    fi

    # Authenticate Docker to ECR
    echo -e "${BLUE}Authenticating Docker to ECR...${NC}"
    docker_login > /dev/null 2>&1

    # Tag local image
    echo -e "${BLUE}Tagging local image...${NC}"
    docker tag "$local_image" "$repo_uri:$tag"

    # Push image
    echo -e "${BLUE}Pushing image...${NC}"
    docker push "$repo_uri:$tag"

    echo -e "${GREEN}Image pushed successfully${NC}"
    echo -e "${BLUE}Image URI: $repo_uri:$tag${NC}"
}

# Pull image from ECR
pull_image() {
    local repo_name=$1
    local image_tag=$2

    if [ -z "$repo_name" ] || [ -z "$image_tag" ]; then
        echo -e "${RED}Error: Repository name and image tag are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Pulling image from ECR repository: $repo_name${NC}"

    # Get repository URI
    local repo_uri=$(aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --query 'repositories[0].repositoryUri' \
        --output text)

    if [ -z "$repo_uri" ]; then
        echo -e "${RED}Error: Repository not found: $repo_name${NC}"
        exit 1
    fi

    # Authenticate Docker to ECR
    echo -e "${BLUE}Authenticating Docker to ECR...${NC}"
    docker_login > /dev/null 2>&1

    # Pull image
    echo -e "${BLUE}Pulling image...${NC}"
    docker pull "$repo_uri:$image_tag"

    echo -e "${GREEN}Image pulled successfully${NC}"
    echo -e "${BLUE}Image: $repo_uri:$image_tag${NC}"
}

# Get repository URI
get_repository_uri() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting repository URI for: $repo_name${NC}"
    aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --query 'repositories[0].repositoryUri' \
        --output text
}

# Set lifecycle policy
set_lifecycle_policy() {
    local repo_name=$1
    local policy_file=$2

    if [ -z "$repo_name" ] || [ -z "$policy_file" ]; then
        echo -e "${RED}Error: Repository name and policy file are required${NC}"
        exit 1
    fi

    if [ ! -f "$policy_file" ]; then
        echo -e "${RED}Error: Policy file does not exist: $policy_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting lifecycle policy for repository: $repo_name${NC}"
    aws ecr put-lifecycle-policy \
        --repository-name "$repo_name" \
        --lifecycle-policy-text "file://$policy_file"
    echo -e "${GREEN}Lifecycle policy set successfully${NC}"
}

# Get lifecycle policy
get_lifecycle_policy() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting lifecycle policy for repository: $repo_name${NC}"
    aws ecr get-lifecycle-policy \
        --repository-name "$repo_name" \
        --query 'lifecyclePolicyText' \
        --output text | jq '.'
}

# Set repository policy
set_repository_policy() {
    local repo_name=$1
    local policy_file=$2

    if [ -z "$repo_name" ] || [ -z "$policy_file" ]; then
        echo -e "${RED}Error: Repository name and policy file are required${NC}"
        exit 1
    fi

    if [ ! -f "$policy_file" ]; then
        echo -e "${RED}Error: Policy file does not exist: $policy_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting repository policy for: $repo_name${NC}"
    aws ecr set-repository-policy \
        --repository-name "$repo_name" \
        --policy-text "file://$policy_file"
    echo -e "${GREEN}Repository policy set successfully${NC}"
}

# Get repository policy
get_repository_policy() {
    local repo_name=$1
    if [ -z "$repo_name" ]; then
        echo -e "${RED}Error: Repository name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting repository policy for: $repo_name${NC}"
    aws ecr get-repository-policy \
        --repository-name "$repo_name" \
        --query 'policyText' \
        --output text | jq '.'
}

# Scan image for vulnerabilities
scan_image() {
    local repo_name=$1
    local image_tag=$2

    if [ -z "$repo_name" ] || [ -z "$image_tag" ]; then
        echo -e "${RED}Error: Repository name and image tag are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Starting vulnerability scan for: $repo_name:$image_tag${NC}"
    aws ecr start-image-scan \
        --repository-name "$repo_name" \
        --image-id imageTag="$image_tag"
    echo -e "${GREEN}Image scan started successfully${NC}"
    echo -e "${BLUE}Use 'get-scan-findings' to view results after scan completes${NC}"
}

# Get scan findings
get_scan_findings() {
    local repo_name=$1
    local image_tag=$2

    if [ -z "$repo_name" ] || [ -z "$image_tag" ]; then
        echo -e "${RED}Error: Repository name and image tag are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting scan findings for: $repo_name:$image_tag${NC}"
    aws ecr describe-image-scan-findings \
        --repository-name "$repo_name" \
        --image-id imageTag="$image_tag"
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    list-repositories)
        list_repositories
        ;;
    create-repository)
        create_repository "$@"
        ;;
    delete-repository)
        delete_repository "$@"
        ;;
    describe-repository)
        describe_repository "$@"
        ;;
    get-login)
        get_login
        ;;
    docker-login)
        docker_login
        ;;
    list-images)
        list_images "$@"
        ;;
    describe-images)
        describe_images "$@"
        ;;
    tag-image)
        tag_image "$@"
        ;;
    delete-image)
        delete_image "$@"
        ;;
    push-image)
        push_image "$@"
        ;;
    pull-image)
        pull_image "$@"
        ;;
    get-repository-uri)
        get_repository_uri "$@"
        ;;
    set-lifecycle-policy)
        set_lifecycle_policy "$@"
        ;;
    get-lifecycle-policy)
        get_lifecycle_policy "$@"
        ;;
    set-repository-policy)
        set_repository_policy "$@"
        ;;
    get-repository-policy)
        get_repository_policy "$@"
        ;;
    scan-image)
        scan_image "$@"
        ;;
    get-scan-findings)
        get_scan_findings "$@"
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac
