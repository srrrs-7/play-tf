# CLI Scripts Rules

Applies to: `cli/**/*.sh`

## Script Structure

All scripts follow this pattern:
```bash
#!/bin/bash
set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Script description comment

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    # List all commands
    exit 1
}

# Function implementations...

# Main command router
case "$1" in
    command-name)
        function_name "${@:2}"
        ;;
    *)
        usage
        ;;
esac
```

## Common Library Usage

Source common functions from `cli/lib/`:
```bash
source "$SCRIPT_DIR/../lib/common.sh"
```

Available helpers:
- `common.sh` - Core utilities (colors, logging, AWS validation, IAM helpers)
- `dynamodb-helpers.sh` - DynamoDB operations
- `lambda-helpers.sh` - Lambda function operations
- `apigw-helpers.sh` - API Gateway operations
- `cloudfront-helpers.sh` - CloudFront operations

## Color-Coded Output

Use predefined color variables:
```bash
echo -e "${GREEN}Success message${NC}"
echo -e "${RED}Error message${NC}"
echo -e "${YELLOW}Warning message${NC}"
echo -e "${BLUE}Info message${NC}"
```

Or logging functions (output to stderr):
```bash
log_info "Information"
log_warn "Warning"
log_error "Error"
log_step "Step description"
log_success "Success"
```

## Parameter Validation

Use helper functions:
```bash
require_param "$bucket_name" "Bucket name"
require_file "$file_path" "Source file"
require_directory "$dir_path" "Source directory"
```

## Destructive Operations

Always confirm before destructive actions:
```bash
confirm_action "This will delete bucket: $bucket_name"
# User must type "yes" to proceed
```

## Architecture Scripts Pattern

Architecture scripts (e.g., `apigw-lambda-dynamodb/`) provide:
- `deploy <name>` - Create all resources
- `destroy <name>` - Delete all resources
- `status` - Show deployed resources
- Individual resource management commands

## Terraform Integration

Some CLI scripts include `tf/` subdirectory with Terraform configs:
```
cli/{architecture}/
├── script.sh      # AWS CLI operations
├── tf/            # Terraform configuration
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── README.md
```

## Region Handling

Default region is `ap-northeast-1`:
```bash
local region=${AWS_DEFAULT_REGION:-ap-northeast-1}
```

Handle `us-east-1` S3 bucket creation specially (no LocationConstraint).
