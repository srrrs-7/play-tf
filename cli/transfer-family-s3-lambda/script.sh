#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# AWS Transfer Family → S3 → Lambda Architecture Script
# Provides operations for SFTP/FTPS file transfer processing

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "AWS Transfer Family → S3 → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy SFTP processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "Transfer Family:"
    echo "  server-create <name>                       - Create SFTP server"
    echo "  server-delete <id>                         - Delete server"
    echo "  server-list                                - List servers"
    echo "  server-start <id>                          - Start server"
    echo "  server-stop <id>                           - Stop server"
    echo "  user-create <server-id> <username> <bucket> - Create user"
    echo "  user-delete <server-id> <username>         - Delete user"
    echo "  user-list <server-id>                      - List users"
    echo "  ssh-key-add <server-id> <username> <key>   - Add SSH public key"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  bucket-list                                - List buckets"
    echo "  files-list <bucket> [prefix]               - List transferred files"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>            - Create function"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo ""
    exit 1
}

# Transfer Family Functions
server_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Server name required"; exit 1; }

    log_step "Creating SFTP server: $name"
    local account_id=$(get_account_id)

    # Create logging role
    local log_role="${name}-transfer-logging-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"transfer.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$log_role" --assume-role-policy-document "$trust" 2>/dev/null || true

    local log_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:$DEFAULT_REGION:$account_id:log-group:/aws/transfer/*"
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$log_role" --policy-name "${name}-logging" --policy-document "$log_policy"

    sleep 10

    local server_id=$(aws transfer create-server \
        --endpoint-type PUBLIC \
        --identity-provider-type SERVICE_MANAGED \
        --protocols SFTP \
        --logging-role "arn:aws:iam::$account_id:role/$log_role" \
        --tags "Key=Name,Value=$name" \
        --query 'ServerId' --output text)

    log_info "Server created: $server_id"
    echo "Server ID: $server_id"

    # Wait for server to be online
    log_info "Waiting for server to come online..."
    for i in {1..30}; do
        local state=$(aws transfer describe-server --server-id "$server_id" --query 'Server.State' --output text)
        if [ "$state" == "ONLINE" ]; then
            local endpoint=$(aws transfer describe-server --server-id "$server_id" --query 'Server.EndpointDetails.VpcEndpointId' --output text)
            log_info "Server is online"
            echo "Endpoint: $server_id.server.transfer.$DEFAULT_REGION.amazonaws.com"
            return 0
        fi
        sleep 10
    done

    log_warn "Server is still starting..."
}

server_delete() {
    local server_id=$1
    [ -z "$server_id" ] && { log_error "Server ID required"; exit 1; }

    log_warn "Deleting server: $server_id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws transfer delete-server --server-id "$server_id"
    log_info "Server deleted"
}

server_list() {
    aws transfer list-servers --query 'Servers[].{ServerId:ServerId,State:State,EndpointType:EndpointType,Protocols:Protocols}' --output table
}

server_start() {
    local server_id=$1
    [ -z "$server_id" ] && { log_error "Server ID required"; exit 1; }
    aws transfer start-server --server-id "$server_id"
    log_info "Server starting"
}

server_stop() {
    local server_id=$1
    [ -z "$server_id" ] && { log_error "Server ID required"; exit 1; }
    aws transfer stop-server --server-id "$server_id"
    log_info "Server stopping"
}

user_create() {
    local server_id=$1
    local username=$2
    local bucket=$3

    if [ -z "$server_id" ] || [ -z "$username" ] || [ -z "$bucket" ]; then
        log_error "Server ID, username, and bucket required"
        exit 1
    fi

    log_step "Creating user: $username"
    local account_id=$(get_account_id)

    # Create user role
    local role_name="${username}-transfer-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"transfer.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": "arn:aws:s3:::$bucket"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
            "Resource": "arn:aws:s3:::$bucket/*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${username}-s3" --policy-document "$s3_policy"

    sleep 5

    aws transfer create-user \
        --server-id "$server_id" \
        --user-name "$username" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --home-directory "/$bucket/$username"

    log_info "User created: $username"
    echo "Home directory: /$bucket/$username"
}

user_delete() {
    local server_id=$1
    local username=$2

    if [ -z "$server_id" ] || [ -z "$username" ]; then
        log_error "Server ID and username required"
        exit 1
    fi

    aws transfer delete-user --server-id "$server_id" --user-name "$username"
    log_info "User deleted"
}

user_list() {
    local server_id=$1
    [ -z "$server_id" ] && { log_error "Server ID required"; exit 1; }
    aws transfer list-users --server-id "$server_id" --query 'Users[].{UserName:UserName,Role:Role,HomeDirectory:HomeDirectory}' --output table
}

ssh_key_add() {
    local server_id=$1
    local username=$2
    local key_file=$3

    if [ -z "$server_id" ] || [ -z "$username" ] || [ -z "$key_file" ]; then
        log_error "Server ID, username, and SSH key file required"
        exit 1
    fi

    local key_body=$(cat "$key_file")
    aws transfer import-ssh-public-key \
        --server-id "$server_id" \
        --user-name "$username" \
        --ssh-public-key-body "$key_body"

    log_info "SSH key added for $username"
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

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
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

bucket_list() {
    aws s3api list-buckets --query 'Buckets[].Name' --output table
}

files_list() {
    local bucket=$1
    local prefix=${2:-""}
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
    else
        aws s3 ls "s3://$bucket/" --recursive --human-readable
    fi
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Name and zip file required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 60

    log_info "Lambda created"
}

lambda_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Function name required"; exit 1; }
    aws lambda delete-function --function-name "$name"
    log_info "Lambda deleted"
}

lambda_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' --output table
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying Transfer Family → S3 → Lambda stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket with EventBridge
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-sftp-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Enable EventBridge notifications
    aws s3api put-bucket-notification-configuration \
        --bucket "$bucket_name" \
        --notification-configuration '{"EventBridgeConfiguration": {}}'

    # Create Lambda processor
    log_step "Creating Lambda processor..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { S3Client, GetObjectCommand, CopyObjectCommand } = require('@aws-sdk/client-s3');
const s3 = new S3Client({});

exports.handler = async (event) => {
    console.log('Processing S3 event from Transfer Family:', JSON.stringify(event, null, 2));

    // Handle EventBridge event format
    const bucket = event.detail?.bucket?.name || event.Records?.[0]?.s3?.bucket?.name;
    const key = event.detail?.object?.key || event.Records?.[0]?.s3?.object?.key;

    if (!bucket || !key) {
        console.log('No S3 info found in event');
        return { statusCode: 400, body: 'Invalid event' };
    }

    console.log(`Processing file: s3://${bucket}/${key}`);

    try {
        // Get file metadata
        const headResult = await s3.send(new GetObjectCommand({
            Bucket: bucket,
            Key: key
        }));

        const fileInfo = {
            bucket,
            key,
            size: headResult.ContentLength,
            contentType: headResult.ContentType,
            lastModified: headResult.LastModified,
            uploadedBy: key.split('/')[0], // User folder
            timestamp: new Date().toISOString()
        };

        console.log('File info:', fileInfo);

        // Copy to processed folder
        const processedKey = key.replace(/^([^\/]+)\//, '$1/processed/');
        await s3.send(new CopyObjectCommand({
            Bucket: bucket,
            Key: processedKey,
            CopySource: `${bucket}/${key}`,
            Metadata: {
                'processed-at': new Date().toISOString(),
                'original-key': key
            },
            MetadataDirective: 'REPLACE'
        }));

        console.log(`File processed and copied to: ${processedKey}`);

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'File processed successfully',
                original: key,
                processed: processedKey,
                ...fileInfo
            })
        };

    } catch (error) {
        console.error('Error processing file:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message })
        };
    }
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local lambda_role="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$lambda_role" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$lambda_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:CopyObject"],"Resource":"arn:aws:s3:::$bucket_name/*"}]}
EOF
)
    aws iam put-role-policy --role-name "$lambda_role" --policy-name "${name}-s3" --policy-document "$s3_policy"

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$lambda_role" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 60 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    local lambda_arn=$(aws lambda get-function --function-name "${name}-processor" --query 'Configuration.FunctionArn' --output text)

    # Create EventBridge rule for S3 events
    log_step "Creating EventBridge rule..."
    local pattern=$(cat << EOF
{
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
        "bucket": {"name": ["$bucket_name"]}
    }
}
EOF
)

    aws events put-rule \
        --name "${name}-s3-trigger" \
        --event-pattern "$pattern" \
        --state ENABLED 2>/dev/null || true

    aws lambda add-permission \
        --function-name "${name}-processor" \
        --statement-id "eventbridge-invoke" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$DEFAULT_REGION:$account_id:rule/${name}-s3-trigger" 2>/dev/null || true

    aws events put-targets \
        --rule "${name}-s3-trigger" \
        --targets "Id=lambda-target,Arn=$lambda_arn"

    # Create Transfer Family server
    log_step "Creating SFTP server..."
    local log_role="${name}-transfer-logging-role"
    local log_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"transfer.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$log_role" --assume-role-policy-document "$log_trust" 2>/dev/null || true

    local log_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"arn:aws:logs:$DEFAULT_REGION:$account_id:log-group:/aws/transfer/*"}]}
EOF
)
    aws iam put-role-policy --role-name "$log_role" --policy-name "${name}-logging" --policy-document "$log_policy"

    sleep 10

    local server_id=$(aws transfer create-server \
        --endpoint-type PUBLIC \
        --identity-provider-type SERVICE_MANAGED \
        --protocols SFTP \
        --logging-role "arn:aws:iam::$account_id:role/$log_role" \
        --tags "Key=Name,Value=${name}-server" \
        --query 'ServerId' --output text 2>/dev/null)

    # Create sample user role
    local user_role="${name}-sftp-user-role"
    local user_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"transfer.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$user_role" --assume-role-policy-document "$user_trust" 2>/dev/null || true

    local user_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {"Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": "arn:aws:s3:::$bucket_name"},
        {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], "Resource": "arn:aws:s3:::$bucket_name/*"}
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$user_role" --policy-name "${name}-s3" --policy-document "$user_policy"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Lambda Processor: ${name}-processor"
    echo "SFTP Server ID: $server_id"
    echo "SFTP Endpoint: $server_id.server.transfer.$DEFAULT_REGION.amazonaws.com"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Create an SFTP user:"
    echo "   $0 user-create $server_id myuser $bucket_name"
    echo ""
    echo "2. Add SSH public key for the user:"
    echo "   $0 ssh-key-add $server_id myuser ~/.ssh/id_rsa.pub"
    echo ""
    echo "3. Connect via SFTP:"
    echo "   sftp -i ~/.ssh/id_rsa myuser@$server_id.server.transfer.$DEFAULT_REGION.amazonaws.com"
    echo ""
    echo "4. Check processed files:"
    echo "   $0 files-list $bucket_name"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Find and delete Transfer server
    local server_id=$(aws transfer list-servers --query "Servers[?Tags[?Key=='Name'&&Value=='${name}-server']].ServerId" --output text 2>/dev/null)
    if [ -n "$server_id" ] && [ "$server_id" != "None" ]; then
        # Delete users first
        local users=$(aws transfer list-users --server-id "$server_id" --query 'Users[].UserName' --output text 2>/dev/null)
        for user in $users; do
            aws transfer delete-user --server-id "$server_id" --user-name "$user" 2>/dev/null || true
        done
        aws transfer delete-server --server-id "$server_id" 2>/dev/null || true
    fi

    # Delete EventBridge rule
    aws events remove-targets --rule "${name}-s3-trigger" --ids lambda-target 2>/dev/null || true
    aws events delete-rule --name "${name}-s3-trigger" 2>/dev/null || true

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-sftp-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM roles
    for role in "${name}-processor-role" "${name}-transfer-logging-role" "${name}-sftp-user-role"; do
        aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null | \
            xargs -I {} aws iam delete-role-policy --role-name "$role" --policy-name {} 2>/dev/null || true
        aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | \
            xargs -I {} aws iam detach-role-policy --role-name "$role" --policy-arn {} 2>/dev/null || true
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    done

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Transfer Family Servers ===${NC}"
    server_list
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    bucket_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    server-create) server_create "$@" ;;
    server-delete) server_delete "$@" ;;
    server-list) server_list ;;
    server-start) server_start "$@" ;;
    server-stop) server_stop "$@" ;;
    user-create) user_create "$@" ;;
    user-delete) user_delete "$@" ;;
    user-list) user_list "$@" ;;
    ssh-key-add) ssh_key_add "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    files-list) files_list "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
