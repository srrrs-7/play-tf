#!/bin/bash

set -e

# AWS Glue Jobs → S3 Architecture Script
# Provides operations for ETL jobs with S3 data lake storage

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "AWS Glue Jobs → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy Glue ETL stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "Glue Jobs:"
    echo "  job-create <name> <script-s3-path> <bucket> - Create Glue job"
    echo "  job-delete <name>                          - Delete Glue job"
    echo "  job-list                                   - List Glue jobs"
    echo "  job-run <name> [args]                      - Run Glue job"
    echo "  job-runs <name>                            - List job runs"
    echo "  job-status <name> <run-id>                 - Get run status"
    echo "  job-stop <name> <run-id>                   - Stop running job"
    echo "  job-logs <name> <run-id>                   - View job logs"
    echo ""
    echo "Glue Crawlers:"
    echo "  crawler-create <name> <bucket> <prefix>    - Create crawler"
    echo "  crawler-delete <name>                      - Delete crawler"
    echo "  crawler-list                               - List crawlers"
    echo "  crawler-run <name>                         - Run crawler"
    echo "  crawler-status <name>                      - Get crawler status"
    echo ""
    echo "Glue Database:"
    echo "  database-create <name>                     - Create database"
    echo "  database-delete <name>                     - Delete database"
    echo "  database-list                              - List databases"
    echo "  tables-list <database>                     - List tables in database"
    echo ""
    echo "Scripts:"
    echo "  script-upload <bucket> <local-file>        - Upload Glue script to S3"
    echo "  script-list <bucket>                       - List scripts in S3"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  bucket-list                                - List buckets"
    echo "  object-list <bucket> [prefix]              - List objects"
    echo ""
    exit 1
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_aws_cli() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured"
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

# Glue Job Functions
job_create() {
    local name=$1
    local script_path=$2
    local bucket=$3

    if [ -z "$name" ] || [ -z "$script_path" ] || [ -z "$bucket" ]; then
        log_error "Job name, script S3 path, and output bucket required"
        exit 1
    fi

    log_step "Creating Glue job: $name"
    local account_id=$(get_account_id)

    # Create Glue role if not exists
    local role_name="${name}-glue-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:ListBucket"
        ],
        "Resource": [
            "arn:aws:s3:::$bucket",
            "arn:aws:s3:::$bucket/*"
        ]
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
        --default-arguments "{
            \"--job-language\": \"python\",
            \"--output-bucket\": \"$bucket\",
            \"--enable-metrics\": \"true\",
            \"--enable-continuous-cloudwatch-log\": \"true\"
        }" \
        --glue-version "4.0" \
        --number-of-workers 2 \
        --worker-type "G.1X"

    log_info "Glue job created"
}

job_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Job name required"; exit 1; }
    aws glue delete-job --job-name "$name"
    log_info "Glue job deleted"
}

job_list() {
    aws glue get-jobs --query 'Jobs[].{Name:Name,Role:Role,GlueVersion:GlueVersion,Workers:NumberOfWorkers}' --output table
}

job_run() {
    local name=$1
    local args=${2:-"{}"}

    [ -z "$name" ] && { log_error "Job name required"; exit 1; }

    log_step "Starting Glue job: $name"
    local run_id=$(aws glue start-job-run \
        --job-name "$name" \
        --arguments "$args" \
        --query 'JobRunId' --output text)

    log_info "Job run started: $run_id"
    echo "$run_id"
}

job_runs() {
    local name=$1
    [ -z "$name" ] && { log_error "Job name required"; exit 1; }
    aws glue get-job-runs --job-name "$name" --query 'JobRuns[].{RunId:Id,State:JobRunState,StartedOn:StartedOn,ExecutionTime:ExecutionTime}' --output table
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

job_stop() {
    local name=$1
    local run_id=$2

    if [ -z "$name" ] || [ -z "$run_id" ]; then
        log_error "Job name and run ID required"
        exit 1
    fi

    aws glue batch-stop-job-run --job-name "$name" --job-run-ids "$run_id"
    log_info "Job run stopped"
}

job_logs() {
    local name=$1
    local run_id=$2

    if [ -z "$name" ] || [ -z "$run_id" ]; then
        log_error "Job name and run ID required"
        exit 1
    fi

    local log_group="/aws-glue/jobs/logs-v2"
    aws logs get-log-events \
        --log-group-name "$log_group" \
        --log-stream-name "${run_id}" \
        --query 'events[].message' --output text 2>/dev/null || \
    log_warn "No logs available yet or log stream not found"
}

# Glue Crawler Functions
crawler_create() {
    local name=$1
    local bucket=$2
    local prefix=$3

    if [ -z "$name" ] || [ -z "$bucket" ]; then
        log_error "Crawler name and bucket required"
        exit 1
    fi

    local s3_path="s3://$bucket"
    if [ -n "$prefix" ]; then
        s3_path="$s3_path/$prefix"
    fi

    log_step "Creating Glue crawler: $name"
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

    # Create database for crawler
    aws glue create-database --database-input "{\"Name\": \"${name}_db\"}" 2>/dev/null || true

    aws glue create-crawler \
        --name "$name" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --database-name "${name}_db" \
        --targets "{
            \"S3Targets\": [{
                \"Path\": \"$s3_path\"
            }]
        }"

    log_info "Crawler created"
}

crawler_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Crawler name required"; exit 1; }
    aws glue delete-crawler --name "$name"
    log_info "Crawler deleted"
}

crawler_list() {
    aws glue get-crawlers --query 'Crawlers[].{Name:Name,Database:DatabaseName,State:State,LastCrawl:LastCrawl.Status}' --output table
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

# Database Functions
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

database_list() {
    aws glue get-databases --query 'DatabaseList[].{Name:Name,CreateTime:CreateTime}' --output table
}

tables_list() {
    local database=$1
    [ -z "$database" ] && { log_error "Database name required"; exit 1; }
    aws glue get-tables --database-name "$database" --query 'TableList[].{Name:Name,TableType:TableType,Location:StorageDescriptor.Location}' --output table
}

# Script Functions
script_upload() {
    local bucket=$1
    local local_file=$2

    if [ -z "$bucket" ] || [ -z "$local_file" ]; then
        log_error "Bucket and local file required"
        exit 1
    fi

    local key="scripts/$(basename "$local_file")"
    aws s3 cp "$local_file" "s3://$bucket/$key"
    log_info "Script uploaded to s3://$bucket/$key"
    echo "s3://$bucket/$key"
}

script_list() {
    local bucket=$1
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }
    aws s3 ls "s3://$bucket/scripts/" 2>/dev/null || log_warn "No scripts found"
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

object_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    else
        aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    fi
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying AWS Glue Jobs → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create S3 buckets
    log_step "Creating S3 buckets..."
    local data_bucket="${name}-glue-data-${account_id}"
    local scripts_bucket="${name}-glue-scripts-${account_id}"

    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$data_bucket" 2>/dev/null || log_info "Data bucket already exists"
        aws s3api create-bucket --bucket "$scripts_bucket" 2>/dev/null || log_info "Scripts bucket already exists"
    else
        aws s3api create-bucket --bucket "$data_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Data bucket already exists"
        aws s3api create-bucket --bucket "$scripts_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Scripts bucket already exists"
    fi

    # Create sample data
    log_step "Creating sample data..."
    cat << 'EOF' > /tmp/sample_data.json
{"id": 1, "name": "Product A", "category": "Electronics", "price": 299.99, "quantity": 100}
{"id": 2, "name": "Product B", "category": "Clothing", "price": 49.99, "quantity": 250}
{"id": 3, "name": "Product C", "category": "Electronics", "price": 599.99, "quantity": 50}
{"id": 4, "name": "Product D", "category": "Home", "price": 89.99, "quantity": 150}
{"id": 5, "name": "Product E", "category": "Clothing", "price": 79.99, "quantity": 200}
EOF
    aws s3 cp /tmp/sample_data.json "s3://$data_bucket/input/products/sample_data.json"

    # Create Glue ETL script
    log_step "Creating Glue ETL script..."
    cat << 'EOF' > /tmp/etl_script.py
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import col, sum as spark_sum, avg, count

# Get job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'output-bucket'])

# Initialize contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

output_bucket = args['output-bucket']

print(f"Starting ETL job: {args['JOB_NAME']}")
print(f"Output bucket: {output_bucket}")

# Read input data
input_path = f"s3://{output_bucket}/input/products/"
print(f"Reading from: {input_path}")

# Read JSON data
df = spark.read.json(input_path)
print(f"Records read: {df.count()}")
df.show()

# Transform: Aggregate by category
category_summary = df.groupBy("category").agg(
    count("id").alias("product_count"),
    spark_sum("quantity").alias("total_quantity"),
    avg("price").alias("avg_price")
)

print("Category Summary:")
category_summary.show()

# Write results
output_path = f"s3://{output_bucket}/output/category_summary/"
print(f"Writing to: {output_path}")

category_summary.write \
    .mode("overwrite") \
    .parquet(output_path)

# Also write as JSON for easy viewing
json_output_path = f"s3://{output_bucket}/output/category_summary_json/"
category_summary.write \
    .mode("overwrite") \
    .json(json_output_path)

print("ETL job completed successfully!")

job.commit()
EOF
    aws s3 cp /tmp/etl_script.py "s3://$scripts_bucket/scripts/etl_script.py"

    # Create IAM role for Glue
    log_step "Creating IAM role..."
    local role_name="${name}-glue-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:ListBucket"
        ],
        "Resource": [
            "arn:aws:s3:::$data_bucket",
            "arn:aws:s3:::$data_bucket/*",
            "arn:aws:s3:::$scripts_bucket",
            "arn:aws:s3:::$scripts_bucket/*"
        ]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    sleep 10

    # Create Glue database
    log_step "Creating Glue database..."
    aws glue create-database --database-input "{\"Name\": \"${name}_db\"}" 2>/dev/null || log_info "Database already exists"

    # Create Glue job
    log_step "Creating Glue job..."
    aws glue create-job \
        --name "${name}-etl-job" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --command "{
            \"Name\": \"glueetl\",
            \"ScriptLocation\": \"s3://$scripts_bucket/scripts/etl_script.py\",
            \"PythonVersion\": \"3\"
        }" \
        --default-arguments "{
            \"--job-language\": \"python\",
            \"--output-bucket\": \"$data_bucket\",
            \"--enable-metrics\": \"true\",
            \"--enable-continuous-cloudwatch-log\": \"true\",
            \"--enable-spark-ui\": \"true\",
            \"--spark-event-logs-path\": \"s3://$data_bucket/spark-logs/\"
        }" \
        --glue-version "4.0" \
        --number-of-workers 2 \
        --worker-type "G.1X" 2>/dev/null || log_info "Job already exists"

    # Create Glue crawler
    log_step "Creating Glue crawler..."
    local crawler_role="${name}-crawler-role"
    aws iam create-role --role-name "$crawler_role" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$crawler_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local crawler_policy=$(cat << EOF
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
    aws iam put-role-policy --role-name "$crawler_role" --policy-name "${name}-s3-read" --policy-document "$crawler_policy"

    sleep 5

    aws glue create-crawler \
        --name "${name}-crawler" \
        --role "arn:aws:iam::$account_id:role/$crawler_role" \
        --database-name "${name}_db" \
        --targets "{
            \"S3Targets\": [
                {\"Path\": \"s3://$data_bucket/input/\"},
                {\"Path\": \"s3://$data_bucket/output/\"}
            ]
        }" 2>/dev/null || log_info "Crawler already exists"

    rm -f /tmp/sample_data.json /tmp/etl_script.py

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Data Bucket: $data_bucket"
    echo "Scripts Bucket: $scripts_bucket"
    echo "Database: ${name}_db"
    echo "ETL Job: ${name}-etl-job"
    echo "Crawler: ${name}-crawler"
    echo ""
    echo "Run the ETL job:"
    echo "  aws glue start-job-run --job-name '${name}-etl-job'"
    echo ""
    echo "Check job status:"
    echo "  aws glue get-job-runs --job-name '${name}-etl-job'"
    echo ""
    echo "Run crawler to catalog data:"
    echo "  aws glue start-crawler --name '${name}-crawler'"
    echo ""
    echo "Check output after job completes:"
    echo "  aws s3 ls s3://$data_bucket/output/ --recursive"
    echo ""
    echo "View tables in database:"
    echo "  aws glue get-tables --database-name '${name}_db'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Stop any running job runs
    log_step "Stopping running jobs..."
    local runs=$(aws glue get-job-runs --job-name "${name}-etl-job" --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text 2>/dev/null)
    for run in $runs; do
        aws glue batch-stop-job-run --job-name "${name}-etl-job" --job-run-ids "$run" 2>/dev/null || true
    done

    # Delete crawler
    log_step "Deleting crawler..."
    aws glue stop-crawler --name "${name}-crawler" 2>/dev/null || true
    aws glue delete-crawler --name "${name}-crawler" 2>/dev/null || true

    # Delete job
    log_step "Deleting Glue job..."
    aws glue delete-job --job-name "${name}-etl-job" 2>/dev/null || true

    # Delete tables and database
    log_step "Deleting database..."
    local tables=$(aws glue get-tables --database-name "${name}_db" --query 'TableList[].Name' --output text 2>/dev/null)
    for table in $tables; do
        aws glue delete-table --database-name "${name}_db" --name "$table" 2>/dev/null || true
    done
    aws glue delete-database --name "${name}_db" 2>/dev/null || true

    # Delete S3 buckets
    local data_bucket="${name}-glue-data-${account_id}"
    local scripts_bucket="${name}-glue-scripts-${account_id}"
    aws s3 rb "s3://$data_bucket" --force 2>/dev/null || true
    aws s3 rb "s3://$scripts_bucket" --force 2>/dev/null || true

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
    echo -e "${BLUE}=== Glue Jobs ===${NC}"
    job_list
    echo -e "\n${BLUE}=== Glue Crawlers ===${NC}"
    crawler_list
    echo -e "\n${BLUE}=== Glue Databases ===${NC}"
    database_list
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
    job-create) job_create "$@" ;;
    job-delete) job_delete "$@" ;;
    job-list) job_list ;;
    job-run) job_run "$@" ;;
    job-runs) job_runs "$@" ;;
    job-status) job_status "$@" ;;
    job-stop) job_stop "$@" ;;
    job-logs) job_logs "$@" ;;
    crawler-create) crawler_create "$@" ;;
    crawler-delete) crawler_delete "$@" ;;
    crawler-list) crawler_list ;;
    crawler-run) crawler_run "$@" ;;
    crawler-status) crawler_status "$@" ;;
    database-create) database_create "$@" ;;
    database-delete) database_delete "$@" ;;
    database-list) database_list ;;
    tables-list) tables_list "$@" ;;
    script-upload) script_upload "$@" ;;
    script-list) script_list "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    object-list) object_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
