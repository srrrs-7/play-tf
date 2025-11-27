#!/bin/bash

set -e

# RDS → DMS → S3 → Glue → Redshift Architecture Script
# Provides operations for database migration and ETL pipeline

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
    echo "RDS → DMS → S3 → Glue → Redshift Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy migration pipeline (partial)"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "RDS (Source):"
    echo "  rds-create <id> <engine> <user> <pass>     - Create RDS instance (mysql/postgres)"
    echo "  rds-delete <id>                            - Delete RDS instance"
    echo "  rds-list                                   - List RDS instances"
    echo "  rds-describe <id>                          - Describe RDS instance"
    echo ""
    echo "DMS:"
    echo "  replication-create <name>                  - Create replication instance"
    echo "  replication-delete <name>                  - Delete replication instance"
    echo "  replication-list                           - List replication instances"
    echo "  endpoint-create <name> <type> <engine> <host> <db> <user> <pass> - Create endpoint"
    echo "  endpoint-delete <arn>                      - Delete endpoint"
    echo "  endpoint-list                              - List endpoints"
    echo "  endpoint-test <replication-arn> <endpoint-arn> - Test endpoint connection"
    echo "  task-create <name> <repl-arn> <src-arn> <tgt-arn> <mapping> - Create migration task"
    echo "  task-delete <arn>                          - Delete task"
    echo "  task-list                                  - List tasks"
    echo "  task-start <arn>                           - Start task"
    echo "  task-stop <arn>                            - Stop task"
    echo ""
    echo "S3 (Staging):"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  data-list <bucket> [prefix]                - List migrated data"
    echo ""
    echo "Glue:"
    echo "  database-create <name>                     - Create Glue database"
    echo "  crawler-create <name> <bucket> <db>        - Create crawler"
    echo "  crawler-run <name>                         - Run crawler"
    echo "  job-create <name> <script> <conn>          - Create ETL job"
    echo "  job-run <name>                             - Run ETL job"
    echo ""
    echo "Redshift (Target):"
    echo "  redshift-create <id> <db> <user> <pass>    - Create Redshift cluster"
    echo "  redshift-delete <id>                       - Delete cluster"
    echo "  redshift-list                              - List clusters"
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

# RDS Functions
rds_create() {
    local id=$1
    local engine=$2
    local user=$3
    local password=$4

    if [ -z "$id" ] || [ -z "$engine" ] || [ -z "$user" ] || [ -z "$password" ]; then
        log_error "Instance ID, engine (mysql/postgres), username, and password required"
        exit 1
    fi

    log_step "Creating RDS instance: $id ($engine)"

    aws rds create-db-instance \
        --db-instance-identifier "$id" \
        --db-instance-class db.t3.micro \
        --engine "$engine" \
        --master-username "$user" \
        --master-user-password "$password" \
        --allocated-storage 20 \
        --publicly-accessible \
        --backup-retention-period 1

    log_info "RDS instance creation initiated (takes 5-10 minutes)"
    log_info "Check status with: $0 rds-describe $id"
}

rds_delete() {
    local id=$1
    [ -z "$id" ] && { log_error "Instance ID required"; exit 1; }

    log_warn "Deleting RDS instance: $id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws rds delete-db-instance --db-instance-identifier "$id" --skip-final-snapshot --delete-automated-backups
    log_info "RDS instance deletion initiated"
}

rds_list() {
    aws rds describe-db-instances --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Endpoint:Endpoint.Address}' --output table
}

rds_describe() {
    local id=$1
    [ -z "$id" ] && { log_error "Instance ID required"; exit 1; }
    aws rds describe-db-instances --db-instance-identifier "$id" --output json
}

# DMS Functions
replication_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Replication instance name required"; exit 1; }

    log_step "Creating DMS replication instance: $name"

    local subnet_group="${name}-subnet-group"
    local subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(get_default_vpc)" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')

    aws dms create-replication-subnet-group \
        --replication-subnet-group-identifier "$subnet_group" \
        --replication-subnet-group-description "DMS subnet group" \
        --subnet-ids ${subnets//,/ } 2>/dev/null || true

    aws dms create-replication-instance \
        --replication-instance-identifier "$name" \
        --replication-instance-class dms.t3.micro \
        --replication-subnet-group-identifier "$subnet_group" \
        --publicly-accessible

    log_info "Replication instance creation initiated (takes 5-10 minutes)"
}

replication_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Replication instance name required"; exit 1; }

    aws dms delete-replication-instance --replication-instance-arn "$(aws dms describe-replication-instances --filters Name=replication-instance-id,Values=$name --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)"
    log_info "Replication instance deletion initiated"
}

replication_list() {
    aws dms describe-replication-instances --query 'ReplicationInstances[].{ID:ReplicationInstanceIdentifier,Status:ReplicationInstanceStatus,Class:ReplicationInstanceClass}' --output table
}

endpoint_create() {
    local name=$1
    local type=$2
    local engine=$3
    local host=$4
    local database=$5
    local user=$6
    local password=$7

    if [ -z "$name" ] || [ -z "$type" ] || [ -z "$engine" ] || [ -z "$host" ] || [ -z "$database" ] || [ -z "$user" ] || [ -z "$password" ]; then
        log_error "Name, type (source/target), engine, host, database, username, and password required"
        exit 1
    fi

    log_step "Creating DMS endpoint: $name"

    aws dms create-endpoint \
        --endpoint-identifier "$name" \
        --endpoint-type "$type" \
        --engine-name "$engine" \
        --server-name "$host" \
        --database-name "$database" \
        --username "$user" \
        --password "$password" \
        --port 3306

    log_info "Endpoint created"
}

endpoint_delete() {
    local arn=$1
    [ -z "$arn" ] && { log_error "Endpoint ARN required"; exit 1; }
    aws dms delete-endpoint --endpoint-arn "$arn"
    log_info "Endpoint deleted"
}

endpoint_list() {
    aws dms describe-endpoints --query 'Endpoints[].{ID:EndpointIdentifier,Type:EndpointType,Engine:EngineName,Status:Status}' --output table
}

endpoint_test() {
    local replication_arn=$1
    local endpoint_arn=$2

    if [ -z "$replication_arn" ] || [ -z "$endpoint_arn" ]; then
        log_error "Replication instance ARN and endpoint ARN required"
        exit 1
    fi

    aws dms test-connection \
        --replication-instance-arn "$replication_arn" \
        --endpoint-arn "$endpoint_arn"

    log_info "Connection test initiated"
}

task_create() {
    local name=$1
    local replication_arn=$2
    local source_arn=$3
    local target_arn=$4
    local mapping=$5

    if [ -z "$name" ] || [ -z "$replication_arn" ] || [ -z "$source_arn" ] || [ -z "$target_arn" ] || [ -z "$mapping" ]; then
        log_error "Task name, replication ARN, source ARN, target ARN, and table mapping file required"
        exit 1
    fi

    log_step "Creating DMS task: $name"

    aws dms create-replication-task \
        --replication-task-identifier "$name" \
        --source-endpoint-arn "$source_arn" \
        --target-endpoint-arn "$target_arn" \
        --replication-instance-arn "$replication_arn" \
        --migration-type full-load-and-cdc \
        --table-mappings "file://$mapping"

    log_info "Replication task created"
}

task_delete() {
    local arn=$1
    [ -z "$arn" ] && { log_error "Task ARN required"; exit 1; }
    aws dms delete-replication-task --replication-task-arn "$arn"
    log_info "Task deleted"
}

task_list() {
    aws dms describe-replication-tasks --query 'ReplicationTasks[].{ID:ReplicationTaskIdentifier,Status:Status,MigrationType:MigrationType}' --output table
}

task_start() {
    local arn=$1
    [ -z "$arn" ] && { log_error "Task ARN required"; exit 1; }
    aws dms start-replication-task --replication-task-arn "$arn" --start-replication-task-type start-replication
    log_info "Task starting"
}

task_stop() {
    local arn=$1
    [ -z "$arn" ] && { log_error "Task ARN required"; exit 1; }
    aws dms stop-replication-task --replication-task-arn "$arn"
    log_info "Task stopping"
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

crawler_create() {
    local name=$1
    local bucket=$2
    local database=$3

    if [ -z "$name" ] || [ -z "$bucket" ] || [ -z "$database" ]; then
        log_error "Crawler name, bucket, and database required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-crawler-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket"],"Resource":["arn:aws:s3:::$bucket","arn:aws:s3:::$bucket/*"]}]}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3" --policy-document "$policy"

    sleep 10

    aws glue create-crawler \
        --name "$name" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --database-name "$database" \
        --targets "{\"S3Targets\":[{\"Path\":\"s3://$bucket/\"}]}"

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
    local script=$2
    local connection=$3

    if [ -z "$name" ] || [ -z "$script" ] || [ -z "$connection" ]; then
        log_error "Job name, script path, and connection required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-glue-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    sleep 10

    aws glue create-job \
        --name "$name" \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --command "{\"Name\":\"glueetl\",\"ScriptLocation\":\"$script\",\"PythonVersion\":\"3\"}" \
        --connections "{\"Connections\":[\"$connection\"]}" \
        --glue-version "4.0" \
        --number-of-workers 2 \
        --worker-type "G.1X"

    log_info "Job created"
}

job_run() {
    local name=$1
    [ -z "$name" ] && { log_error "Job name required"; exit 1; }
    aws glue start-job-run --job-name "$name"
    log_info "Job started"
}

# Redshift Functions
redshift_create() {
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
}

redshift_delete() {
    local id=$1
    [ -z "$id" ] && { log_error "Cluster ID required"; exit 1; }

    log_warn "Deleting Redshift cluster: $id"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws redshift delete-cluster --cluster-identifier "$id" --skip-final-cluster-snapshot
    log_info "Cluster deletion initiated"
}

redshift_list() {
    aws redshift describe-clusters --query 'Clusters[].{ID:ClusterIdentifier,Status:ClusterStatus,Endpoint:Endpoint.Address}' --output table
}

# Full Stack Deployment (Partial - creates infrastructure without actual migration)
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying RDS → DMS → S3 → Glue → Redshift stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket for staging
    log_step "Creating S3 staging bucket..."
    local bucket_name="${name}-migration-staging-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Create Glue database
    log_step "Creating Glue database..."
    aws glue create-database --database-input "{\"Name\": \"${name}_migration_db\"}" 2>/dev/null || log_info "Database exists"

    # Create sample table mapping
    log_step "Creating sample DMS table mapping..."
    cat << 'EOF' > /tmp/table-mapping.json
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-all-tables",
            "object-locator": {
                "schema-name": "%",
                "table-name": "%"
            },
            "rule-action": "include"
        }
    ]
}
EOF
    aws s3 cp /tmp/table-mapping.json "s3://$bucket_name/config/"

    echo ""
    echo -e "${GREEN}Partial deployment complete!${NC}"
    echo ""
    echo "S3 Staging Bucket: $bucket_name"
    echo "Glue Database: ${name}_migration_db"
    echo "Table Mapping: s3://$bucket_name/config/table-mapping.json"
    echo ""
    echo -e "${YELLOW}Next steps for complete pipeline:${NC}"
    echo ""
    echo "1. Create source RDS instance:"
    echo "   $0 rds-create ${name}-source mysql admin YourPassword123!"
    echo ""
    echo "2. Create DMS replication instance:"
    echo "   $0 replication-create ${name}-replication"
    echo ""
    echo "3. Wait for RDS and replication instance, then create endpoints:"
    echo "   # Get RDS endpoint"
    echo "   RDS_HOST=\$(aws rds describe-db-instances --db-instance-identifier ${name}-source --query 'DBInstances[0].Endpoint.Address' --output text)"
    echo ""
    echo "   # Create source endpoint"
    echo "   $0 endpoint-create ${name}-source source mysql \$RDS_HOST mydb admin YourPassword123!"
    echo ""
    echo "   # Create S3 target endpoint (for staging)"
    echo "   aws dms create-endpoint --endpoint-identifier ${name}-s3-target --endpoint-type target --engine-name s3 --s3-settings 'BucketName=$bucket_name,ServiceAccessRoleArn=arn:aws:iam::$account_id:role/${name}-dms-s3-role'"
    echo ""
    echo "4. Create Redshift cluster:"
    echo "   $0 redshift-create ${name}-redshift warehouse admin YourPassword123!"
    echo ""
    echo "5. Create and run DMS migration task"
    echo ""
    echo "6. Run Glue crawler and ETL to load into Redshift"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete DMS resources
    log_step "Deleting DMS resources..."
    # Note: In production, iterate through actual resources

    # Delete Redshift
    aws redshift delete-cluster --cluster-identifier "${name}-redshift" --skip-final-cluster-snapshot 2>/dev/null || true

    # Delete RDS
    aws rds delete-db-instance --db-instance-identifier "${name}-source" --skip-final-snapshot --delete-automated-backups 2>/dev/null || true

    # Delete Glue
    aws glue delete-database --name "${name}_migration_db" 2>/dev/null || true

    # Delete S3
    local bucket_name="${name}-migration-staging-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== RDS Instances ===${NC}"
    rds_list
    echo -e "\n${BLUE}=== DMS Replication Instances ===${NC}"
    replication_list
    echo -e "\n${BLUE}=== DMS Endpoints ===${NC}"
    endpoint_list
    echo -e "\n${BLUE}=== DMS Tasks ===${NC}"
    task_list
    echo -e "\n${BLUE}=== Redshift Clusters ===${NC}"
    redshift_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    rds-create) rds_create "$@" ;;
    rds-delete) rds_delete "$@" ;;
    rds-list) rds_list ;;
    rds-describe) rds_describe "$@" ;;
    replication-create) replication_create "$@" ;;
    replication-delete) replication_delete "$@" ;;
    replication-list) replication_list ;;
    endpoint-create) endpoint_create "$@" ;;
    endpoint-delete) endpoint_delete "$@" ;;
    endpoint-list) endpoint_list ;;
    endpoint-test) endpoint_test "$@" ;;
    task-create) task_create "$@" ;;
    task-delete) task_delete "$@" ;;
    task-list) task_list ;;
    task-start) task_start "$@" ;;
    task-stop) task_stop "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    data-list) data_list "$@" ;;
    database-create) database_create "$@" ;;
    crawler-create) crawler_create "$@" ;;
    crawler-run) crawler_run "$@" ;;
    job-create) job_create "$@" ;;
    job-run) job_run "$@" ;;
    redshift-create) redshift_create "$@" ;;
    redshift-delete) redshift_delete "$@" ;;
    redshift-list) redshift_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
