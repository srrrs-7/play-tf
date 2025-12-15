#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 Tables → Athena Architecture Script
# Provides operations for S3 Tables (Apache Iceberg) with Athena queries
# S3 Tables are fully managed Iceberg tables optimized for analytics workloads

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 Tables → Athena Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                                - Deploy S3 Tables with Athena integration"
    echo "  destroy <stack-name>                               - Destroy all resources"
    echo "  status                                             - Show status"
    echo ""
    echo "Table Bucket Operations:"
    echo "  table-bucket-create <name>                         - Create table bucket"
    echo "  table-bucket-delete <name>                         - Delete table bucket"
    echo "  table-bucket-list                                  - List table buckets"
    echo "  table-bucket-get <arn>                             - Get table bucket details"
    echo ""
    echo "Namespace Operations:"
    echo "  namespace-create <bucket-arn> <name>               - Create namespace"
    echo "  namespace-delete <bucket-arn> <name>               - Delete namespace"
    echo "  namespace-list <bucket-arn>                        - List namespaces"
    echo ""
    echo "Table Operations:"
    echo "  table-create <bucket-arn> <namespace> <name>       - Create Iceberg table"
    echo "  table-delete <bucket-arn> <namespace> <name>       - Delete table"
    echo "  table-list <bucket-arn> [namespace]                - List tables"
    echo "  table-get <bucket-arn> <namespace> <name>          - Get table details"
    echo ""
    echo "Athena Integration:"
    echo "  catalog-create                                     - Create s3tablescatalog in Glue"
    echo "  catalog-delete                                     - Delete s3tablescatalog"
    echo "  catalog-get                                        - Get s3tablescatalog details"
    echo "  query <catalog/bucket> <namespace> <sql>           - Run Athena query"
    echo "  query-status <query-id>                            - Get query status"
    echo "  query-results <query-id>                           - Get query results"
    echo ""
    echo "Lake Formation:"
    echo "  lf-register <bucket-arn> <role-arn>                - Register table bucket with Lake Formation"
    echo "  lf-grant <bucket-arn> <principal-arn>              - Grant Lake Formation permissions"
    echo ""
    echo "Examples:"
    echo "  $0 deploy my-analytics"
    echo "  $0 table-bucket-create my-data-bucket"
    echo "  $0 namespace-create arn:aws:s3tables:ap-northeast-1:123456789012:bucket/my-bucket my_namespace"
    echo "  $0 query 's3tablescatalog/my-bucket' my_namespace 'SELECT * FROM my_table LIMIT 10'"
    echo ""
    exit 1
}

# =============================================================================
# Table Bucket Functions
# =============================================================================
table_bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Table bucket name required"; exit 1; }

    log_step "Creating table bucket: $name"
    aws s3tables create-table-bucket \
        --region "$DEFAULT_REGION" \
        --name "$name"
    log_info "Table bucket created"
}

table_bucket_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Table bucket name required"; exit 1; }

    log_warn "Deleting table bucket: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)
    local bucket_arn="arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/${name}"

    # Delete all tables first
    local namespaces=$(aws s3tables list-namespaces --table-bucket-arn "$bucket_arn" --query 'namespaces[].namespace[0]' --output text 2>/dev/null || echo "")
    for ns in $namespaces; do
        local tables=$(aws s3tables list-tables --table-bucket-arn "$bucket_arn" --namespace "$ns" --query 'tables[].name' --output text 2>/dev/null || echo "")
        for table in $tables; do
            aws s3tables delete-table --table-bucket-arn "$bucket_arn" --namespace "$ns" --name "$table" 2>/dev/null || true
        done
        aws s3tables delete-namespace --table-bucket-arn "$bucket_arn" --namespace "$ns" 2>/dev/null || true
    done

    aws s3tables delete-table-bucket \
        --region "$DEFAULT_REGION" \
        --table-bucket-arn "$bucket_arn"
    log_info "Table bucket deleted"
}

table_bucket_list() {
    aws s3tables list-table-buckets \
        --region "$DEFAULT_REGION" \
        --query 'tableBuckets[].{Name:name,ARN:arn,CreatedAt:createdAt}' \
        --output table
}

table_bucket_get() {
    local arn=$1
    [ -z "$arn" ] && { log_error "Table bucket ARN required"; exit 1; }

    aws s3tables get-table-bucket \
        --table-bucket-arn "$arn" \
        --output json
}

# =============================================================================
# Namespace Functions
# =============================================================================
namespace_create() {
    local bucket_arn=$1
    local name=$2

    if [ -z "$bucket_arn" ] || [ -z "$name" ]; then
        log_error "Table bucket ARN and namespace name required"
        exit 1
    fi

    log_step "Creating namespace: $name"
    aws s3tables create-namespace \
        --table-bucket-arn "$bucket_arn" \
        --namespace "$name"
    log_info "Namespace created"
}

namespace_delete() {
    local bucket_arn=$1
    local name=$2

    if [ -z "$bucket_arn" ] || [ -z "$name" ]; then
        log_error "Table bucket ARN and namespace name required"
        exit 1
    fi

    log_warn "Deleting namespace: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Delete all tables in namespace first
    local tables=$(aws s3tables list-tables --table-bucket-arn "$bucket_arn" --namespace "$name" --query 'tables[].name' --output text 2>/dev/null || echo "")
    for table in $tables; do
        aws s3tables delete-table --table-bucket-arn "$bucket_arn" --namespace "$name" --name "$table" 2>/dev/null || true
    done

    aws s3tables delete-namespace \
        --table-bucket-arn "$bucket_arn" \
        --namespace "$name"
    log_info "Namespace deleted"
}

namespace_list() {
    local bucket_arn=$1
    [ -z "$bucket_arn" ] && { log_error "Table bucket ARN required"; exit 1; }

    aws s3tables list-namespaces \
        --table-bucket-arn "$bucket_arn" \
        --query 'namespaces[].{Namespace:namespace[0],CreatedAt:createdAt}' \
        --output table
}

# =============================================================================
# Table Functions
# =============================================================================
table_create() {
    local bucket_arn=$1
    local namespace=$2
    local name=$3

    if [ -z "$bucket_arn" ] || [ -z "$namespace" ] || [ -z "$name" ]; then
        log_error "Table bucket ARN, namespace, and table name required"
        exit 1
    fi

    log_step "Creating table: $name"
    aws s3tables create-table \
        --table-bucket-arn "$bucket_arn" \
        --namespace "$namespace" \
        --name "$name" \
        --format ICEBERG
    log_info "Table created"
}

table_delete() {
    local bucket_arn=$1
    local namespace=$2
    local name=$3

    if [ -z "$bucket_arn" ] || [ -z "$namespace" ] || [ -z "$name" ]; then
        log_error "Table bucket ARN, namespace, and table name required"
        exit 1
    fi

    log_warn "Deleting table: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws s3tables delete-table \
        --table-bucket-arn "$bucket_arn" \
        --namespace "$namespace" \
        --name "$name"
    log_info "Table deleted"
}

table_list() {
    local bucket_arn=$1
    local namespace=$2

    [ -z "$bucket_arn" ] && { log_error "Table bucket ARN required"; exit 1; }

    if [ -n "$namespace" ]; then
        aws s3tables list-tables \
            --table-bucket-arn "$bucket_arn" \
            --namespace "$namespace" \
            --query 'tables[].{Name:name,Namespace:namespace[0],Type:type,CreatedAt:createdAt}' \
            --output table
    else
        aws s3tables list-tables \
            --table-bucket-arn "$bucket_arn" \
            --query 'tables[].{Name:name,Namespace:namespace[0],Type:type,CreatedAt:createdAt}' \
            --output table
    fi
}

table_get() {
    local bucket_arn=$1
    local namespace=$2
    local name=$3

    if [ -z "$bucket_arn" ] || [ -z "$namespace" ] || [ -z "$name" ]; then
        log_error "Table bucket ARN, namespace, and table name required"
        exit 1
    fi

    aws s3tables get-table \
        --table-bucket-arn "$bucket_arn" \
        --namespace "$namespace" \
        --name "$name" \
        --output json
}

# =============================================================================
# Athena Integration Functions
# =============================================================================
catalog_create() {
    local account_id=$(get_account_id)

    log_step "Creating s3tablescatalog in Glue..."

    local catalog_json=$(cat << EOF
{
    "Name": "s3tablescatalog",
    "CatalogInput": {
        "FederatedCatalog": {
            "Identifier": "arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/*",
            "ConnectionName": "aws:s3tables"
        },
        "CreateDatabaseDefaultPermissions": [],
        "CreateTableDefaultPermissions": [],
        "AllowFullTableExternalDataAccess": "True"
    }
}
EOF
)

    echo "$catalog_json" > /tmp/s3tables-catalog.json
    aws glue create-catalog \
        --region "$DEFAULT_REGION" \
        --cli-input-json file:///tmp/s3tables-catalog.json
    rm -f /tmp/s3tables-catalog.json

    log_info "s3tablescatalog created"
}

catalog_delete() {
    log_warn "Deleting s3tablescatalog"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws glue delete-catalog \
        --catalog-id s3tablescatalog \
        --region "$DEFAULT_REGION" 2>/dev/null || true
    log_info "s3tablescatalog deleted"
}

catalog_get() {
    aws glue get-catalog \
        --catalog-id s3tablescatalog \
        --region "$DEFAULT_REGION" \
        --output json
}

athena_query() {
    local catalog_bucket=$1
    local namespace=$2
    local sql=$3
    local workgroup=${4:-"primary"}

    if [ -z "$catalog_bucket" ] || [ -z "$namespace" ] || [ -z "$sql" ]; then
        log_error "Catalog/bucket, namespace, and SQL query required"
        echo "Usage: $0 query <s3tablescatalog/bucket-name> <namespace> '<sql>'"
        exit 1
    fi

    log_step "Executing query..."
    local query_id=$(aws athena start-query-execution \
        --query-string "$sql" \
        --query-execution-context "{\"Catalog\": \"${catalog_bucket}\", \"Database\": \"${namespace}\"}" \
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
    aws athena get-query-execution \
        --query-execution-id "$query_id" \
        --query 'QueryExecution.{Status:Status,Statistics:Statistics}' \
        --output json
}

query_results() {
    local query_id=$1
    [ -z "$query_id" ] && { log_error "Query ID required"; exit 1; }
    aws athena get-query-results \
        --query-execution-id "$query_id" \
        --output table
}

# =============================================================================
# Lake Formation Functions
# =============================================================================
lf_register() {
    local bucket_arn=$1
    local role_arn=$2

    if [ -z "$bucket_arn" ] || [ -z "$role_arn" ]; then
        log_error "Table bucket ARN and IAM role ARN required"
        exit 1
    fi

    log_step "Registering table bucket with Lake Formation..."

    local input_json=$(cat << EOF
{
    "ResourceArn": "${bucket_arn}",
    "WithFederation": true,
    "RoleArn": "${role_arn}"
}
EOF
)

    echo "$input_json" > /tmp/lf-register.json
    aws lakeformation register-resource \
        --region "$DEFAULT_REGION" \
        --with-privileged-access \
        --cli-input-json file:///tmp/lf-register.json
    rm -f /tmp/lf-register.json

    log_info "Table bucket registered with Lake Formation"
}

lf_grant() {
    local catalog_bucket=$1
    local principal_arn=$2

    if [ -z "$catalog_bucket" ] || [ -z "$principal_arn" ]; then
        log_error "Catalog/bucket ID and principal ARN required"
        echo "Usage: $0 lf-grant <account_id:s3tablescatalog/bucket-name> <user-or-role-arn>"
        exit 1
    fi

    local account_id=$(get_account_id)

    log_step "Granting Lake Formation permissions..."
    aws lakeformation grant-permissions \
        --region "$DEFAULT_REGION" \
        --cli-input-json "{
            \"Principal\": {
                \"DataLakePrincipalIdentifier\": \"${principal_arn}\"
            },
            \"Resource\": {
                \"Catalog\": {
                    \"Id\": \"${catalog_bucket}\"
                }
            },
            \"Permissions\": [\"ALL\"]
        }"

    log_info "Permissions granted"
}

# =============================================================================
# Full Stack Deployment
# =============================================================================
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 Tables → Athena stack: $name"
    local account_id=$(get_account_id)

    # Create Athena results bucket
    log_step "Creating Athena results bucket..."
    local results_bucket="${name}-athena-results-${account_id}"
    create_bucket_if_not_exists "$results_bucket"

    # Create table bucket
    log_step "Creating table bucket..."
    local table_bucket_name="${name}-tables"
    aws s3tables create-table-bucket \
        --region "$DEFAULT_REGION" \
        --name "$table_bucket_name" 2>/dev/null || log_info "Table bucket already exists"

    local table_bucket_arn="arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/${table_bucket_name}"

    # Create namespace
    log_step "Creating namespace..."
    local namespace_name="${name//-/_}_data"
    aws s3tables create-namespace \
        --table-bucket-arn "$table_bucket_arn" \
        --namespace "$namespace_name" 2>/dev/null || log_info "Namespace already exists"

    # Create IAM role for Lake Formation
    log_step "Creating IAM role for Lake Formation..."
    local role_name="${name}-s3tables-lf-role"

    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LakeFormationDataAccessPolicy",
            "Effect": "Allow",
            "Principal": {
                "Service": "lakeformation.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:SetContext",
                "sts:SetSourceIdentity"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "${account_id}"
                }
            }
        }
    ]
}
EOF
)

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    local s3tables_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LakeFormationPermissionsForS3ListTableBucket",
            "Effect": "Allow",
            "Action": ["s3tables:ListTableBuckets"],
            "Resource": ["*"]
        },
        {
            "Sid": "LakeFormationDataAccessPermissionsForS3TableBucket",
            "Effect": "Allow",
            "Action": [
                "s3tables:CreateTableBucket",
                "s3tables:GetTableBucket",
                "s3tables:CreateNamespace",
                "s3tables:GetNamespace",
                "s3tables:ListNamespaces",
                "s3tables:DeleteNamespace",
                "s3tables:DeleteTableBucket",
                "s3tables:CreateTable",
                "s3tables:DeleteTable",
                "s3tables:GetTable",
                "s3tables:ListTables",
                "s3tables:RenameTable",
                "s3tables:UpdateTableMetadataLocation",
                "s3tables:GetTableMetadataLocation",
                "s3tables:GetTableData",
                "s3tables:PutTableData"
            ],
            "Resource": ["arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/*"]
        }
    ]
}
EOF
)

    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "${name}-s3tables-access" \
        --policy-document "$s3tables_policy" 2>/dev/null || true

    sleep 10

    # Register with Lake Formation
    log_step "Registering table bucket with Lake Formation..."
    local lf_input=$(cat << EOF
{
    "ResourceArn": "arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/*",
    "WithFederation": true,
    "RoleArn": "arn:aws:iam::${account_id}:role/${role_name}"
}
EOF
)
    echo "$lf_input" > /tmp/lf-register-${name}.json
    aws lakeformation register-resource \
        --region "$DEFAULT_REGION" \
        --with-privileged-access \
        --cli-input-json file:///tmp/lf-register-${name}.json 2>/dev/null || log_info "Already registered with Lake Formation"
    rm -f /tmp/lf-register-${name}.json

    # Create s3tablescatalog
    log_step "Creating s3tablescatalog in Glue..."
    local catalog_json=$(cat << EOF
{
    "Name": "s3tablescatalog",
    "CatalogInput": {
        "FederatedCatalog": {
            "Identifier": "arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/*",
            "ConnectionName": "aws:s3tables"
        },
        "CreateDatabaseDefaultPermissions": [],
        "CreateTableDefaultPermissions": [],
        "AllowFullTableExternalDataAccess": "True"
    }
}
EOF
)
    echo "$catalog_json" > /tmp/s3tables-catalog-${name}.json
    aws glue create-catalog \
        --region "$DEFAULT_REGION" \
        --cli-input-json file:///tmp/s3tables-catalog-${name}.json 2>/dev/null || log_info "s3tablescatalog already exists"
    rm -f /tmp/s3tables-catalog-${name}.json

    # Create Athena workgroup
    log_step "Creating Athena workgroup..."
    aws athena create-work-group \
        --name "${name}-workgroup" \
        --configuration "{
            \"ResultConfiguration\": {
                \"OutputLocation\": \"s3://${results_bucket}/athena-results/\"
            },
            \"EnforceWorkGroupConfiguration\": true,
            \"PublishCloudWatchMetricsEnabled\": true
        }" 2>/dev/null || log_info "Workgroup already exists"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Table Bucket: ${table_bucket_name}"
    echo "Table Bucket ARN: ${table_bucket_arn}"
    echo "Namespace: ${namespace_name}"
    echo "Results Bucket: ${results_bucket}"
    echo "Athena Workgroup: ${name}-workgroup"
    echo "Lake Formation Role: ${role_name}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Create a table with schema using Athena:"
    echo "     $0 query 's3tablescatalog/${table_bucket_name}' '${namespace_name}' \\"
    echo "       'CREATE TABLE sales ("
    echo "         order_id string,"
    echo "         customer_id string,"
    echo "         product_name string,"
    echo "         quantity int,"
    echo "         unit_price double,"
    echo "         order_date date"
    echo "       ) TBLPROPERTIES (\"table_type\" = \"iceberg\")' ${name}-workgroup"
    echo ""
    echo "  2. Insert data:"
    echo "     $0 query 's3tablescatalog/${table_bucket_name}' '${namespace_name}' \\"
    echo "       \"INSERT INTO sales VALUES"
    echo "         ('1001', 'C001', 'Laptop', 1, 999.99, DATE '2024-01-15'),"
    echo "         ('1002', 'C002', 'Mouse', 2, 29.99, DATE '2024-01-16')\" ${name}-workgroup"
    echo ""
    echo "  3. Query data:"
    echo "     $0 query 's3tablescatalog/${table_bucket_name}' '${namespace_name}' \\"
    echo "       'SELECT * FROM sales LIMIT 10' ${name}-workgroup"
    echo ""
    echo "Note: S3 Tables use Apache Iceberg format and are fully managed by AWS."
    echo "      Table names and column names must be lowercase."
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)
    local table_bucket_name="${name}-tables"
    local table_bucket_arn="arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/${table_bucket_name}"
    local namespace_name="${name//-/_}_data"

    # Delete Athena workgroup
    log_step "Deleting Athena workgroup..."
    aws athena delete-work-group \
        --work-group "${name}-workgroup" \
        --recursive-delete-option 2>/dev/null || true

    # Delete tables in namespace
    log_step "Deleting tables..."
    local tables=$(aws s3tables list-tables \
        --table-bucket-arn "$table_bucket_arn" \
        --namespace "$namespace_name" \
        --query 'tables[].name' \
        --output text 2>/dev/null || echo "")
    for table in $tables; do
        aws s3tables delete-table \
            --table-bucket-arn "$table_bucket_arn" \
            --namespace "$namespace_name" \
            --name "$table" 2>/dev/null || true
    done

    # Delete namespace
    log_step "Deleting namespace..."
    aws s3tables delete-namespace \
        --table-bucket-arn "$table_bucket_arn" \
        --namespace "$namespace_name" 2>/dev/null || true

    # Delete table bucket
    log_step "Deleting table bucket..."
    aws s3tables delete-table-bucket \
        --table-bucket-arn "$table_bucket_arn" 2>/dev/null || true

    # Deregister from Lake Formation
    log_step "Deregistering from Lake Formation..."
    aws lakeformation deregister-resource \
        --resource-arn "arn:aws:s3tables:${DEFAULT_REGION}:${account_id}:bucket/*" 2>/dev/null || true

    # Delete IAM role
    log_step "Deleting IAM role..."
    local role_name="${name}-s3tables-lf-role"
    aws iam delete-role-policy \
        --role-name "$role_name" \
        --policy-name "${name}-s3tables-access" 2>/dev/null || true
    aws iam delete-role \
        --role-name "$role_name" 2>/dev/null || true

    # Delete results bucket
    log_step "Deleting Athena results bucket..."
    local results_bucket="${name}-athena-results-${account_id}"
    aws s3 rb "s3://${results_bucket}" --force 2>/dev/null || true

    # Note: s3tablescatalog is shared, not deleting it
    log_info "Note: s3tablescatalog is a shared resource and was not deleted"

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== S3 Table Buckets ===${NC}"
    table_bucket_list 2>/dev/null || echo "No table buckets found or s3tables not available in this region"

    echo -e "\n${BLUE}=== s3tablescatalog ===${NC}"
    aws glue get-catalog --catalog-id s3tablescatalog --query 'Catalog.{Name:Name,CreateTime:CreateTime}' --output table 2>/dev/null || echo "s3tablescatalog not found"

    echo -e "\n${BLUE}=== Athena Workgroups ===${NC}"
    aws athena list-work-groups --query 'WorkGroups[].{Name:Name,State:State}' --output table

    echo -e "\n${BLUE}=== Lake Formation Registered Resources ===${NC}"
    aws lakeformation list-resources --query 'ResourceInfoList[?contains(ResourceArn, `s3tables`)].{ARN:ResourceArn,RoleArn:RoleArn}' --output table 2>/dev/null || echo "No S3 Tables resources registered"
}

# =============================================================================
# Main
# =============================================================================
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    table-bucket-create) table_bucket_create "$@" ;;
    table-bucket-delete) table_bucket_delete "$@" ;;
    table-bucket-list) table_bucket_list ;;
    table-bucket-get) table_bucket_get "$@" ;;
    namespace-create) namespace_create "$@" ;;
    namespace-delete) namespace_delete "$@" ;;
    namespace-list) namespace_list "$@" ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    table-list) table_list "$@" ;;
    table-get) table_get "$@" ;;
    catalog-create) catalog_create ;;
    catalog-delete) catalog_delete ;;
    catalog-get) catalog_get ;;
    query) athena_query "$@" ;;
    query-status) query_status "$@" ;;
    query-results) query_results "$@" ;;
    lf-register) lf_register "$@" ;;
    lf-grant) lf_grant "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
