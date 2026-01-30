# CLAUDE.md - CLI Helper Libraries

This directory contains shared bash helper functions for CLI scripts.

## Files Overview

| File | Purpose |
|------|---------|
| `common.sh` | Core utilities, colors, logging, AWS validation, IAM helpers |
| `dynamodb-helpers.sh` | DynamoDB CRUD operations |
| `lambda-helpers.sh` | Lambda function management |
| `apigw-helpers.sh` | API Gateway operations |
| `cloudfront-helpers.sh` | CloudFront distribution management |

## Usage

Source from CLI scripts:
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/lambda-helpers.sh"  # Optional specific helpers
```

## common.sh

### Color Variables
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color
```

### Logging Functions (output to stderr)
```bash
log_info "Information message"
log_warn "Warning message"
log_error "Error message"
log_step "Step description"
log_success "Success message"
```

### Parameter Validation
```bash
require_param "$bucket_name" "Bucket name"     # Exit if empty
require_file "$file_path" "Source file"        # Exit if file doesn't exist
require_directory "$dir_path" "Source dir"     # Exit if directory doesn't exist
```

### Confirmation
```bash
confirm_action "This will delete bucket: $bucket"  # Requires "yes" to proceed
```

### AWS Validation
```bash
check_aws_credentials    # Verify AWS credentials are configured
get_account_id           # Get current AWS account ID
get_region              # Get configured region (default: ap-northeast-1)
```

### IAM Helpers
```bash
create_lambda_role "$role_name" "$policy_arn"
create_ecs_task_role "$role_name" "$policy_document"
attach_policy_to_role "$role_name" "$policy_arn"
```

## dynamodb-helpers.sh

```bash
create_table "$table_name" "$key_schema" "$attribute_definitions"
delete_table "$table_name"
put_item "$table_name" "$item_json"
get_item "$table_name" "$key_json"
query_items "$table_name" "$key_condition"
scan_table "$table_name"
```

## lambda-helpers.sh

```bash
create_function "$function_name" "$role_arn" "$handler" "$runtime" "$zip_file"
update_function_code "$function_name" "$zip_file"
invoke_function "$function_name" "$payload"
delete_function "$function_name"
list_functions
get_function_url "$function_name"
```

## apigw-helpers.sh

```bash
create_rest_api "$api_name"
create_resource "$api_id" "$parent_id" "$path_part"
create_method "$api_id" "$resource_id" "$http_method" "$lambda_arn"
deploy_api "$api_id" "$stage_name"
get_api_url "$api_id" "$stage_name"
```

## cloudfront-helpers.sh

```bash
create_distribution "$origin_domain" "$config_file"
create_invalidation "$distribution_id" "$paths"
get_distribution_domain "$distribution_id"
wait_for_deployment "$distribution_id"
```

## Best Practices

1. Always source `common.sh` first
2. Use logging functions instead of raw `echo`
3. Use `require_*` functions for parameter validation
4. Use `confirm_action` before destructive operations
5. Handle errors with proper exit codes
