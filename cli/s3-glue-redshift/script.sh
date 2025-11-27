#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → Glue → Redshift Architecture Script
# Provides operations for data warehouse ETL

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → Glue → Redshift Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy data warehouse ETL stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3 Data Lake:"
    echo "  bucket-create <name>                       - Create data bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  data-upload <bucket> <file> [prefix]       - Upload data file"
    echo "  data-list <bucket> [prefix]                - List data files"
    echo ""
    echo "Glue ETL:"
    echo "  database-create <name>                     - Create Glue database"
    echo "  database-delete <name>                     - Delete database"
    echo "  crawler-create <name> <bucket> <db>        - Create crawler"
    echo "  crawler-run <name>                         - Run crawler"
    echo "  job-create <name> <script> <bucket> <conn> - Create ETL job"
    echo "  job-run <name>                             - Run ETL job"
    echo "  job-status <name> <run-id>                 - Get job status"
    echo ""
    echo "Glue Connections:"
    echo "  connection-create <name> <cluster> <db> <user> <pass> - Create Redshift connection"
    echo "  connection-delete <name>                   - Delete connection"
    echo "  connection-list                            - List connections"
    echo ""
    echo "Redshift:"
    echo "  cluster-create <id> <db> <user> <pass>     - Create Redshift cluster"
    echo "  cluster-delete <id>                        - Delete cluster"
    echo "  cluster-list                               - List clusters"
    echo "  cluster-describe <id>                      - Describe cluster"
    echo "  cluster-resume <id>                        - Resume paused cluster"
    echo "  cluster-pause <id>                         - Pause cluster"
    echo ""
    echo "Redshift Serverless:"
    echo "  serverless-create <namespace> <workgroup>  - Create serverless endpoint"
    echo "  serverless-delete <namespace> <workgroup>  - Delete serverless"
    echo "  serverless-list                            - List namespaces/workgroups"
    echo ""
    exit 1
}

get_default_vpc() {
    aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text
}

get_default_subnet() {
    local vpc_id=$(get_default_vpc)
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[0].SubnetId' --output text
}

get_default_security_group() {
    local vpc_id=$(get_default_vpc)
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text
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

# Glue Functions
database_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Database name required"; exit 1; }
    aws glue create-database --database-input "{\"Name\": \"$name\"}"
    log_info "Database created"
}

database_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Database name required"; exit 1; }
    aws glue delete-database --name "$name"
    log_info "Database deleted"
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
        --targets "{\"S3Targets\": [{\"Path\": \"s3://$bucket/\"}]}"

    log_info "Crawler created"
}

crawler_run() {
    local name=$1
    [ -z "$name" ] && { log_error "Crawler name required"; exit 1; }
    aws glue start-crawler --name "$name"
    log_info "Crawler started"
}

job_create() {
    local name=$1
    local script_path=$2
    local bucket=$3
    local connection=$4

    if [ -z "$name" ] || [ -z "$script_path" ] || [ -z "$bucket" ] || [ -z "$connection" ]; then
        log_error "Job name, script path, bucket, and connection required"
        exit 1
    fi

    log_step "Creating Glue job: $name"
    local account_id=$(get_account_id)

    local role_name="${name}-glue-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:*"],
        "Resource": ["arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    sleep 10

    aws glue create-job \
        --name "$name" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --command "{
            \"Name\": \"glueetl\",
            \"ScriptLocation\": \"$script_path\",
            \"PythonVersion\": \"3\"
        }" \
        --connections "{\"Connections\": [\"$connection\"]}" \
        --glue-version "4.0" \
        --number-of-workers 2 \
        --worker-type "G.1X"

    log_info "Job created"
}

job_run() {
    local name=$1
    [ -z "$name" ] && { log_error "Job name required"; exit 1; }

    local run_id=$(aws glue start-job-run --job-name "$name" --query 'JobRunId' --output text)
    log_info "Job run started: $run_id"
    echo "$run_id"
}

job_status() {
    local name=$1
    local run_id=$2

    if [ -z "$name" ] || [ -z "$run_id" ]; then
        log_error "Job name and run ID required"
        exit 1
    fi

    aws glue get-job-run --job-name "$name" --run-id "$run_id" --output json
}

# Glue Connection Functions
connection_create() {
    local name=$1
    local cluster_id=$2
    local database=$3
    local user=$4
    local password=$5

    if [ -z "$name" ] || [ -z "$cluster_id" ] || [ -z "$database" ] || [ -z "$user" ] || [ -z "$password" ]; then
        log_error "Connection name, cluster ID, database, username, and password required"
        exit 1
    fi

    log_step "Creating Glue connection: $name"

    local cluster_info=$(aws redshift describe-clusters --cluster-identifier "$cluster_id" --query 'Clusters[0]' --output json)
    local endpoint=$(echo "$cluster_info" | jq -r '.Endpoint.Address')
    local port=$(echo "$cluster_info" | jq -r '.Endpoint.Port')
    local vpc_id=$(echo "$cluster_info" | jq -r '.VpcId')
    local az=$(echo "$cluster_info" | jq -r '.AvailabilityZone')
    local subnet=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=availability-zone,Values=$az" --query 'Subnets[0].SubnetId' --output text)
    local sg=$(echo "$cluster_info" | jq -r '.VpcSecurityGroups[0].VpcSecurityGroupId')

    aws glue create-connection \
        --connection-input "{
            \"Name\": \"$name\",
            \"ConnectionType\": \"JDBC\",
            \"ConnectionProperties\": {
                \"JDBC_CONNECTION_URL\": \"jdbc:redshift://$endpoint:$port/$database\",
                \"USERNAME\": \"$user\",
                \"PASSWORD\": \"$password\"
            },
            \"PhysicalConnectionRequirements\": {
                \"SubnetId\": \"$subnet\",
                \"SecurityGroupIdList\": [\"$sg\"],
                \"AvailabilityZone\": \"$az\"
            }
        }"

    log_info "Connection created"
}

connection_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Connection name required"; exit 1; }
    aws glue delete-connection --connection-name "$name"
    log_info "Connection deleted"
}

connection_list() {
    aws glue get-connections --query 'ConnectionList[].{Name:Name,Type:ConnectionType}' --output table
}

# Redshift Functions
cluster_create() {
    local id=$1
    local database=$2
    local user=$3
    local password=$4

    if [ -z "$id" ] || [ -z "$database" ] || [ -z "$user" ] || [ -z "$password" ]; then
        log_error "Cluster ID, database, username, and password required"
        exit 1
    fi

    log_step "Creating Redshift cluster: $id"

    aws redshift create-cluster \
        --cluster-identifier "$id" \
        --node-type dc2.large \
        --number-of-nodes 1 \
        --master-username "$user" \
        --master-user-password "$password" \
        --db-name "$database" \
        --publicly-accessible

    log_info "Cluster creation initiated (takes 5-10 minutes)"
    log_info "Check status with: $0 cluster-describe $id"
}

cluster_delete() {
    local id=$1
    [ -z "$id" ] && { log_error "Cluster ID required"; exit 1; }

    log_warn "Deleting cluster: $id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws redshift delete-cluster --cluster-identifier "$id" --skip-final-cluster-snapshot
    log_info "Cluster deletion initiated"
}

cluster_list() {
    aws redshift describe-clusters --query 'Clusters[].{Identifier:ClusterIdentifier,Status:ClusterStatus,NodeType:NodeType,DBName:DBName}' --output table
}

cluster_describe() {
    local id=$1
    [ -z "$id" ] && { log_error "Cluster ID required"; exit 1; }
    aws redshift describe-clusters --cluster-identifier "$id" --query 'Clusters[0]' --output json
}

cluster_resume() {
    local id=$1
    [ -z "$id" ] && { log_error "Cluster ID required"; exit 1; }
    aws redshift resume-cluster --cluster-identifier "$id"
    log_info "Cluster resuming"
}

cluster_pause() {
    local id=$1
    [ -z "$id" ] && { log_error "Cluster ID required"; exit 1; }
    aws redshift pause-cluster --cluster-identifier "$id"
    log_info "Cluster pausing"
}

# Redshift Serverless Functions
serverless_create() {
    local namespace=$1
    local workgroup=$2

    if [ -z "$namespace" ] || [ -z "$workgroup" ]; then
        log_error "Namespace and workgroup name required"
        exit 1
    fi

    log_step "Creating Redshift Serverless..."
    local account_id=$(get_account_id)

    # Create namespace
    aws redshift-serverless create-namespace \
        --namespace-name "$namespace" \
        --admin-username admin \
        --admin-user-password "$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)Aa1!" \
        --db-name "warehouse"

    # Create workgroup
    local subnet=$(get_default_subnet)
    local sg=$(get_default_security_group)

    aws redshift-serverless create-workgroup \
        --workgroup-name "$workgroup" \
        --namespace-name "$namespace" \
        --base-capacity 32 \
        --publicly-accessible \
        --subnet-ids "$subnet" \
        --security-group-ids "$sg"

    log_info "Serverless endpoint created"
}

serverless_delete() {
    local namespace=$1
    local workgroup=$2

    if [ -z "$namespace" ] || [ -z "$workgroup" ]; then
        log_error "Namespace and workgroup name required"
        exit 1
    fi

    log_warn "Deleting Redshift Serverless..."
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws redshift-serverless delete-workgroup --workgroup-name "$workgroup" 2>/dev/null || true
    sleep 30
    aws redshift-serverless delete-namespace --namespace-name "$namespace" 2>/dev/null || true
    log_info "Serverless endpoint deleted"
}

serverless_list() {
    echo -e "${BLUE}=== Namespaces ===${NC}"
    aws redshift-serverless list-namespaces --query 'namespaces[].{Name:namespaceName,Status:status,DBName:dbName}' --output table 2>/dev/null || echo "None"
    echo -e "\n${BLUE}=== Workgroups ===${NC}"
    aws redshift-serverless list-workgroups --query 'workgroups[].{Name:workgroupName,Status:status,Namespace:namespaceName}' --output table 2>/dev/null || echo "None"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → Glue → Redshift stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-etl-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket already exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket already exists"
    fi

    # Create sample data
    log_step "Creating sample data..."
    cat << 'EOF' > /tmp/sales_data.csv
order_id,product_id,customer_id,quantity,unit_price,order_date,region
1001,P001,C001,2,299.99,2024-01-15,North
1002,P002,C002,1,499.99,2024-01-15,South
1003,P003,C001,3,99.99,2024-01-16,East
1004,P001,C003,1,299.99,2024-01-16,West
1005,P004,C002,2,149.99,2024-01-17,North
1006,P002,C004,1,499.99,2024-01-17,South
1007,P005,C005,4,79.99,2024-01-18,East
1008,P003,C001,2,99.99,2024-01-18,West
1009,P001,C006,1,299.99,2024-01-19,North
1010,P004,C002,3,149.99,2024-01-19,South
EOF
    aws s3 cp /tmp/sales_data.csv "s3://$bucket_name/input/sales/"

    # Create Glue ETL script
    log_step "Creating Glue ETL script..."
    cat << 'EOF' > /tmp/etl_to_redshift.py
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'redshift_connection', 'redshift_database', 'redshift_table', 's3_path'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from S3
print(f"Reading from: {args['s3_path']}")
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": [args['s3_path']]},
    format="csv",
    format_options={"withHeader": True}
)

print(f"Records read: {datasource.count()}")

# Apply transformations
transformed = datasource.apply_mapping([
    ("order_id", "string", "order_id", "int"),
    ("product_id", "string", "product_id", "string"),
    ("customer_id", "string", "customer_id", "string"),
    ("quantity", "string", "quantity", "int"),
    ("unit_price", "string", "unit_price", "decimal"),
    ("order_date", "string", "order_date", "date"),
    ("region", "string", "region", "string")
])

# Write to Redshift
print(f"Writing to Redshift: {args['redshift_database']}.{args['redshift_table']}")
glueContext.write_dynamic_frame.from_jdbc_conf(
    frame=transformed,
    catalog_connection=args['redshift_connection'],
    connection_options={
        "dbtable": args['redshift_table'],
        "database": args['redshift_database']
    },
    redshift_tmp_dir=f"{args['s3_path'].rsplit('/', 2)[0]}/temp/"
)

print("ETL job completed!")
job.commit()
EOF
    aws s3 cp /tmp/etl_to_redshift.py "s3://$bucket_name/scripts/"

    # Create Glue database
    log_step "Creating Glue catalog..."
    aws glue create-database --database-input "{\"Name\": \"${name}_db\"}" 2>/dev/null || log_info "Database already exists"

    # Create IAM role
    local role_name="${name}-glue-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:*"],
        "Resource": ["arn:aws:s3:::$bucket_name", "arn:aws:s3:::$bucket_name/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    rm -f /tmp/sales_data.csv /tmp/etl_to_redshift.py

    echo ""
    echo -e "${GREEN}Partial deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Glue Database: ${name}_db"
    echo "ETL Script: s3://$bucket_name/scripts/etl_to_redshift.py"
    echo ""
    echo -e "${YELLOW}Next steps (Redshift setup required):${NC}"
    echo ""
    echo "1. Create Redshift cluster:"
    echo "   $0 cluster-create ${name}-cluster warehouse admin YourPassword123!"
    echo ""
    echo "2. Wait for cluster to be available, then create Glue connection:"
    echo "   $0 connection-create ${name}-conn ${name}-cluster warehouse admin YourPassword123!"
    echo ""
    echo "3. Create and run Glue ETL job:"
    echo "   $0 job-create ${name}-etl s3://$bucket_name/scripts/etl_to_redshift.py $bucket_name ${name}-conn"
    echo "   $0 job-run ${name}-etl"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete Glue resources
    aws glue delete-job --job-name "${name}-etl" 2>/dev/null || true
    aws glue delete-connection --connection-name "${name}-conn" 2>/dev/null || true
    aws glue stop-crawler --name "${name}-crawler" 2>/dev/null || true
    aws glue delete-crawler --name "${name}-crawler" 2>/dev/null || true
    aws glue delete-database --name "${name}_db" 2>/dev/null || true

    # Delete Redshift cluster
    aws redshift delete-cluster --cluster-identifier "${name}-cluster" --skip-final-cluster-snapshot 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-etl-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-glue-role" --policy-name "${name}-s3-access" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-glue-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-glue-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-crawler-role" --policy-name "${name}-s3-read" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-crawler-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-crawler-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Redshift Clusters ===${NC}"
    cluster_list
    echo -e "\n${BLUE}=== Glue Connections ===${NC}"
    connection_list
    echo -e "\n${BLUE}=== Glue Jobs ===${NC}"
    aws glue get-jobs --query 'Jobs[].{Name:Name,Role:Role}' --output table 2>/dev/null || echo "None"
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
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
    data-upload) data_upload "$@" ;;
    data-list) data_list "$@" ;;
    database-create) database_create "$@" ;;
    database-delete) database_delete "$@" ;;
    crawler-create) crawler_create "$@" ;;
    crawler-run) crawler_run "$@" ;;
    job-create) job_create "$@" ;;
    job-run) job_run "$@" ;;
    job-status) job_status "$@" ;;
    connection-create) connection_create "$@" ;;
    connection-delete) connection_delete "$@" ;;
    connection-list) connection_list ;;
    cluster-create) cluster_create "$@" ;;
    cluster-delete) cluster_delete "$@" ;;
    cluster-list) cluster_list ;;
    cluster-describe) cluster_describe "$@" ;;
    cluster-resume) cluster_resume "$@" ;;
    cluster-pause) cluster_pause "$@" ;;
    serverless-create) serverless_create "$@" ;;
    serverless-delete) serverless_delete "$@" ;;
    serverless-list) serverless_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
