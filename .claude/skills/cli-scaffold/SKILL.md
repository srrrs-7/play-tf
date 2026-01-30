---
name: cli-scaffold
description: Scaffold a new AWS CLI operation script with guided setup
user-invocable: true
allowed-tools: Bash, Read, Write, Glob
---

# CLI Scaffold Skill

Creates a new AWS CLI operation script following project conventions.

## Usage

```
/cli-scaffold <script-name> [type]
```

- `script-name`: Name of the script/directory
- `type`: `basic` (single service) or `architecture` (multi-service)

## Script Types

### Basic Service Script
For single AWS service operations (e.g., `cognito`, `ses`, `route53`)

```
cli/{service}/
├── script.sh    # Operations script
└── README.md    # Documentation
```

### Architecture Script
For multi-service deployments (e.g., `cognito-lambda-apigw`)

```
cli/{architecture}/
├── script.sh    # CLI operations
├── README.md    # Documentation
└── tf/          # Optional Terraform
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

## Step 1: Create Directory Structure

```bash
mkdir -p cli/{name}
```

## Step 2: Create script.sh

### Basic Template

```bash
#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# {Service} Operations Script
# Provides common {service} operations using AWS CLI

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                              - List all resources"
    echo "  create <name>                     - Create new resource"
    echo "  delete <name>                     - Delete resource"
    echo "  describe <name>                   - Describe resource details"
    echo ""
    exit 1
}

# List resources
list_resources() {
    log_info "Listing resources..."
    aws {service} list-xxx
}

# Create resource
create_resource() {
    local name=$1
    require_param "$name" "Resource name"

    log_info "Creating resource: $name"
    aws {service} create-xxx --name "$name"
    log_success "Resource created successfully"
}

# Delete resource
delete_resource() {
    local name=$1
    require_param "$name" "Resource name"

    confirm_action "This will delete resource: $name"

    log_info "Deleting resource: $name"
    aws {service} delete-xxx --name "$name"
    log_success "Resource deleted successfully"
}

# Main
case "$1" in
    list)
        list_resources
        ;;
    create)
        create_resource "$2"
        ;;
    delete)
        delete_resource "$2"
        ;;
    describe)
        describe_resource "$2"
        ;;
    *)
        usage
        ;;
esac
```

### Architecture Template (with deploy/destroy)

```bash
#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# {Architecture} Deployment Script

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>    - Deploy all resources"
    echo "  destroy <stack-name>   - Destroy all resources"
    echo "  status                 - Show deployment status"
    echo ""
    echo "Individual Resources:"
    echo "  create-{resource1} <name>  - Create {resource1}"
    echo "  delete-{resource1} <name>  - Delete {resource1}"
    echo ""
    exit 1
}

# Deploy all resources
deploy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_step "Deploying stack: $stack_name"

    # Create resources in order
    create_resource1 "$stack_name"
    create_resource2 "$stack_name"
    create_resource3 "$stack_name"

    log_success "Stack deployed successfully!"
    show_status
}

# Destroy all resources
destroy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    confirm_action "This will destroy all resources in stack: $stack_name"

    log_step "Destroying stack: $stack_name"

    # Delete in reverse order
    delete_resource3 "$stack_name"
    delete_resource2 "$stack_name"
    delete_resource1 "$stack_name"

    log_success "Stack destroyed successfully!"
}

# Show status
show_status() {
    log_info "Deployment Status"
    echo "================="
    # List deployed resources
}

case "$1" in
    deploy)
        deploy "$2"
        ;;
    destroy)
        destroy "$2"
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac
```

## Step 3: Make Executable

```bash
chmod +x cli/{name}/script.sh
```

## Step 4: Create README.md

```markdown
# {Name} CLI Script

AWS CLI operations for {description}.

## Prerequisites

- AWS CLI configured
- Appropriate IAM permissions

## Usage

\`\`\`bash
./script.sh <command> [options]
\`\`\`

## Commands

| Command | Description |
|---------|-------------|
| list | List all resources |
| create <name> | Create new resource |
| delete <name> | Delete resource |

## Examples

\`\`\`bash
# List resources
./script.sh list

# Create resource
./script.sh create my-resource

# Delete resource
./script.sh delete my-resource
\`\`\`

## Architecture

{Describe the architecture if applicable}
```

## Step 5: Test Script

```bash
cd cli/{name}
./script.sh  # Should show usage
./script.sh list  # Test basic operation
```

## Available Helper Libraries

From `cli/lib/`:
- `common.sh` - Core utilities (required)
- `dynamodb-helpers.sh` - DynamoDB operations
- `lambda-helpers.sh` - Lambda with IAM
- `apigw-helpers.sh` - API Gateway
- `cloudfront-helpers.sh` - CloudFront
