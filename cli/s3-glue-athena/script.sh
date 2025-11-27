#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → Glue → Athena Architecture Script
# Provides operations for data lake analytics with Athena

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → Glue → Athena Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy data lake analytics stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3 Data Lake:"
    echo "  bucket-create <name>                       - Create data bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  bucket-list                                - List buckets"
    echo "  data-upload <bucket> <file> [prefix]       - Upload data file"
    echo "  data-list <bucket> [prefix]                - List data files"
    echo ""
    echo "Glue Catalog:"
    echo "  database-create <name>                     - Create database"
    echo "  database-delete <name>                     - Delete database"
    echo "  database-list                              - List databases"
    echo "  crawler-create <name> <bucket> <db>        - Create crawler"
    echo "  crawler-run <name>                         - Run crawler"
    echo "  crawler-status <name>                      - Get crawler status"
    echo "  tables-list <database>                     - List tables"
    echo "  table-describe <database> <table>          - Describe table"
    echo ""
    echo "Athena:"
    echo "  workgroup-create <name> <output-bucket>    - Create workgroup"
    echo "  workgroup-delete <name>                    - Delete workgroup"
    echo "  workgroup-list                             - List workgroups"
    echo "  query <database> <sql> [workgroup]         - Run query"
    echo "  query-status <query-id>                    - Get query status"
    echo "  query-results <query-id>                   - Get query results"
    echo "  saved-queries <workgroup>                  - List saved queries"
    echo ""
    exit 1
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

data_upload() {
    local bucket=$1
    local file=$2
    local prefix=${3:-"data"}

    if [ -z "$bucket" ] || [ -z "$file" ]; then
        log_error "Bucket and file required"
        exit 1
    fi

    local key="$prefix/$(basename "$file")"
    aws s3 cp "$file" "s3://$bucket/$key"
    log_info "Data uploaded to s3://$bucket/$key"
}

data_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
    else
        aws s3 ls "s3://$bucket/" --recursive --human-readable
    fi
}

# Glue Catalog Functions
database_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Database name required"; exit 1; }
    aws glue create-database --database-input "{\"Name\": \"$name\"}"
    log_info "Database created"
}

database_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Database name required"; exit 1; }

    # Delete all tables first
    local tables=$(aws glue get-tables --database-name "$name" --query 'TableList[].Name' --output text 2>/dev/null)
    for table in $tables; do
        aws glue delete-table --database-name "$name" --name "$table" 2>/dev/null || true
    done

    aws glue delete-database --name "$name"
    log_info "Database deleted"
}

database_list() {
    aws glue get-databases --query 'DatabaseList[].{Name:Name,CreateTime:CreateTime}' --output table
}

crawler_create() {
    local name=$1
    local bucket=$2
    local database=$3

    if [ -z "$name" ] || [ -z "$bucket" ] || [ -z "$database" ]; then
        log_error "Crawler name, bucket, and database required"
        exit 1
    fi

    log_step "Creating crawler: $name"
    local account_id=$(get_account_id)

    # Create crawler role
    local role_name="${name}-crawler-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:ListBucket"],
        "Resource": ["arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-read" --policy-document "$s3_policy"

    sleep 10

    aws glue create-crawler \
        --name "$name" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --database-name "$database" \
        --targets "{
            \"S3Targets\": [{
                \"Path\": \"s3://$bucket/\"
            }]
        }"

    log_info "Crawler created"
}

crawler_run() {
    local name=$1
    [ -z "$name" ] && { log_error "Crawler name required"; exit 1; }
    aws glue start-crawler --name "$name"
    log_info "Crawler started"
}

crawler_status() {
    local name=$1
    [ -z "$name" ] && { log_error "Crawler name required"; exit 1; }
    aws glue get-crawler --name "$name" --query 'Crawler.{Name:Name,State:State,LastCrawl:LastCrawl}' --output json
}

tables_list() {
    local database=$1
    [ -z "$database" ] && { log_error "Database name required"; exit 1; }
    aws glue get-tables --database-name "$database" --query 'TableList[].{Name:Name,TableType:TableType,Location:StorageDescriptor.Location}' --output table
}

table_describe() {
    local database=$1
    local table=$2

    if [ -z "$database" ] || [ -z "$table" ]; then
        log_error "Database and table name required"
        exit 1
    fi

    aws glue get-table --database-name "$database" --name "$table" --output json
}

# Athena Functions
workgroup_create() {
    local name=$1
    local output_bucket=$2

    if [ -z "$name" ] || [ -z "$output_bucket" ]; then
        log_error "Workgroup name and output bucket required"
        exit 1
    fi

    log_step "Creating Athena workgroup: $name"
    aws athena create-work-group \
        --name "$name" \
        --configuration "{
            \"ResultConfiguration\": {
                \"OutputLocation\": \"s3://$output_bucket/athena-results/\"
            },
            \"EnforceWorkGroupConfiguration\": true,
            \"PublishCloudWatchMetricsEnabled\": true
        }"

    log_info "Workgroup created"
}

workgroup_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Workgroup name required"; exit 1; }
    aws athena delete-work-group --work-group "$name" --recursive-delete-option
    log_info "Workgroup deleted"
}

workgroup_list() {
    aws athena list-work-groups --query 'WorkGroups[].{Name:Name,State:State}' --output table
}

query() {
    local database=$1
    local sql=$2
    local workgroup=${3:-"primary"}

    if [ -z "$database" ] || [ -z "$sql" ]; then
        log_error "Database and SQL query required"
        exit 1
    fi

    log_step "Executing query..."
    local query_id=$(aws athena start-query-execution \
        --query-string "$sql" \
        --query-execution-context "Database=$database" \
        --work-group "$workgroup" \
        --query 'QueryExecutionId' --output text)

    log_info "Query started: $query_id"

    # Wait for completion
    echo "Waiting for query to complete..."
    for i in {1..60}; do
        local state=$(aws athena get-query-execution --query-execution-id "$query_id" --query 'QueryExecution.Status.State' --output text)
        if [ "$state" == "SUCCEEDED" ]; then
            echo -e "\n${GREEN}Query completed successfully!${NC}"
            aws athena get-query-results --query-execution-id "$query_id" --output table
            return 0
        elif [ "$state" == "FAILED" ] || [ "$state" == "CANCELLED" ]; then
            local reason=$(aws athena get-query-execution --query-execution-id "$query_id" --query 'QueryExecution.Status.StateChangeReason' --output text)
            log_error "Query $state: $reason"
            return 1
        fi
        sleep 2
        echo -n "."
    done

    log_warn "Query still running. Check status with: $0 query-status $query_id"
}

query_status() {
    local query_id=$1
    [ -z "$query_id" ] && { log_error "Query ID required"; exit 1; }
    aws athena get-query-execution --query-execution-id "$query_id" --query 'QueryExecution.{Status:Status,Statistics:Statistics}' --output json
}

query_results() {
    local query_id=$1
    [ -z "$query_id" ] && { log_error "Query ID required"; exit 1; }
    aws athena get-query-results --query-execution-id "$query_id" --output table
}

saved_queries() {
    local workgroup=${1:-"primary"}
    aws athena list-named-queries --work-group "$workgroup" --output table
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → Glue → Athena stack: $name"
    local account_id=$(get_account_id)

    # Create S3 buckets
    log_step "Creating S3 buckets..."
    local data_bucket="${name}-datalake-${account_id}"
    local results_bucket="${name}-athena-results-${account_id}"

    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$data_bucket" 2>/dev/null || log_info "Data bucket already exists"
        aws s3api create-bucket --bucket "$results_bucket" 2>/dev/null || log_info "Results bucket already exists"
    else
        aws s3api create-bucket --bucket "$data_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Data bucket already exists"
        aws s3api create-bucket --bucket "$results_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Results bucket already exists"
    fi

    # Create sample data
    log_step "Creating sample data..."
    mkdir -p /tmp/${name}-data

    # Sales data (CSV)
    cat << 'EOF' > /tmp/${name}-data/sales.csv
order_id,customer_id,product_name,category,quantity,unit_price,order_date
1001,C001,Laptop,Electronics,1,999.99,2024-01-15
1002,C002,Mouse,Electronics,2,29.99,2024-01-15
1003,C001,Keyboard,Electronics,1,79.99,2024-01-16
1004,C003,T-Shirt,Clothing,3,24.99,2024-01-16
1005,C002,Jeans,Clothing,2,49.99,2024-01-17
1006,C004,Headphones,Electronics,1,149.99,2024-01-17
1007,C001,Monitor,Electronics,2,299.99,2024-01-18
1008,C005,Shoes,Clothing,1,89.99,2024-01-18
1009,C003,Tablet,Electronics,1,449.99,2024-01-19
1010,C002,Watch,Accessories,1,199.99,2024-01-19
EOF

    # Customers data (JSON)
    cat << 'EOF' > /tmp/${name}-data/customers.json
{"customer_id": "C001", "name": "John Doe", "email": "john@example.com", "city": "New York", "signup_date": "2023-06-15"}
{"customer_id": "C002", "name": "Jane Smith", "email": "jane@example.com", "city": "Los Angeles", "signup_date": "2023-07-20"}
{"customer_id": "C003", "name": "Bob Johnson", "email": "bob@example.com", "city": "Chicago", "signup_date": "2023-08-10"}
{"customer_id": "C004", "name": "Alice Brown", "email": "alice@example.com", "city": "Houston", "signup_date": "2023-09-05"}
{"customer_id": "C005", "name": "Charlie Wilson", "email": "charlie@example.com", "city": "Phoenix", "signup_date": "2023-10-12"}
EOF

    aws s3 cp /tmp/${name}-data/sales.csv "s3://$data_bucket/sales/"
    aws s3 cp /tmp/${name}-data/customers.json "s3://$data_bucket/customers/"

    # Create Glue database
    log_step "Creating Glue database..."
    aws glue create-database --database-input "{\"Name\": \"${name}_db\"}" 2>/dev/null || log_info "Database already exists"

    # Create crawler role
    log_step "Creating IAM role for crawler..."
    local role_name="${name}-crawler-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:ListBucket"],
        "Resource": ["arn:aws:s3:::$data_bucket", "arn:aws:s3:::$data_bucket/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-read" --policy-document "$s3_policy"

    sleep 10

    # Create crawler
    log_step "Creating Glue crawler..."
    aws glue create-crawler \
        --name "${name}-crawler" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --database-name "${name}_db" \
        --targets "{
            \"S3Targets\": [
                {\"Path\": \"s3://$data_bucket/sales/\"},
                {\"Path\": \"s3://$data_bucket/customers/\"}
            ]
        }" 2>/dev/null || log_info "Crawler already exists"

    # Run crawler
    log_step "Running crawler to catalog data..."
    aws glue start-crawler --name "${name}-crawler" 2>/dev/null || true

    # Create Athena workgroup
    log_step "Creating Athena workgroup..."
    aws athena create-work-group \
        --name "${name}-workgroup" \
        --configuration "{
            \"ResultConfiguration\": {
                \"OutputLocation\": \"s3://$results_bucket/athena-results/\"
            },
            \"EnforceWorkGroupConfiguration\": true,
            \"PublishCloudWatchMetricsEnabled\": true
        }" 2>/dev/null || log_info "Workgroup already exists"

    rm -rf /tmp/${name}-data

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Data Bucket: $data_bucket"
    echo "Results Bucket: $results_bucket"
    echo "Database: ${name}_db"
    echo "Crawler: ${name}-crawler"
    echo "Workgroup: ${name}-workgroup"
    echo ""
    echo "Wait for crawler to complete (check status with):"
    echo "  aws glue get-crawler --name '${name}-crawler' --query 'Crawler.State'"
    echo ""
    echo "Sample queries (after crawler completes):"
    echo ""
    echo "  # List all sales"
    echo "  $0 query ${name}_db 'SELECT * FROM sales LIMIT 10' ${name}-workgroup"
    echo ""
    echo "  # Sales by category"
    echo "  $0 query ${name}_db 'SELECT category, COUNT(*) as orders, SUM(quantity * unit_price) as revenue FROM sales GROUP BY category' ${name}-workgroup"
    echo ""
    echo "  # Join customers and sales"
    echo "  $0 query ${name}_db 'SELECT c.name, c.city, s.product_name, s.quantity FROM customers c JOIN sales s ON c.customer_id = s.customer_id' ${name}-workgroup"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete Athena workgroup
    aws athena delete-work-group --work-group "${name}-workgroup" --recursive-delete-option 2>/dev/null || true

    # Delete crawler
    aws glue stop-crawler --name "${name}-crawler" 2>/dev/null || true
    aws glue delete-crawler --name "${name}-crawler" 2>/dev/null || true

    # Delete tables and database
    local tables=$(aws glue get-tables --database-name "${name}_db" --query 'TableList[].Name' --output text 2>/dev/null)
    for table in $tables; do
        aws glue delete-table --database-name "${name}_db" --name "$table" 2>/dev/null || true
    done
    aws glue delete-database --name "${name}_db" 2>/dev/null || true

    # Delete S3 buckets
    local data_bucket="${name}-datalake-${account_id}"
    local results_bucket="${name}-athena-results-${account_id}"
    aws s3 rb "s3://$data_bucket" --force 2>/dev/null || true
    aws s3 rb "s3://$results_bucket" --force 2>/dev/null || true

    # Delete IAM role
    aws iam delete-role-policy --role-name "${name}-crawler-role" --policy-name "${name}-s3-read" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-crawler-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-crawler-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Glue Databases ===${NC}"
    database_list
    echo -e "\n${BLUE}=== Glue Crawlers ===${NC}"
    aws glue get-crawlers --query 'Crawlers[].{Name:Name,State:State,Database:DatabaseName}' --output table 2>/dev/null || echo "No crawlers found"
    echo -e "\n${BLUE}=== Athena Workgroups ===${NC}"
    workgroup_list
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
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    data-upload) data_upload "$@" ;;
    data-list) data_list "$@" ;;
    database-create) database_create "$@" ;;
    database-delete) database_delete "$@" ;;
    database-list) database_list ;;
    crawler-create) crawler_create "$@" ;;
    crawler-run) crawler_run "$@" ;;
    crawler-status) crawler_status "$@" ;;
    tables-list) tables_list "$@" ;;
    table-describe) table_describe "$@" ;;
    workgroup-create) workgroup_create "$@" ;;
    workgroup-delete) workgroup_delete "$@" ;;
    workgroup-list) workgroup_list ;;
    query) query "$@" ;;
    query-status) query_status "$@" ;;
    query-results) query_results "$@" ;;
    saved-queries) saved_queries "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
