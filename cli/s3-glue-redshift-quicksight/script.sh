#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → Glue → Redshift → QuickSight Architecture Script
# Provides operations for end-to-end BI analytics pipeline

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → Glue → Redshift → QuickSight Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy BI analytics pipeline"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3 Data Lake:"
    echo "  bucket-create <name>                       - Create data bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  data-upload <bucket> <file> [prefix]       - Upload data file"
    echo ""
    echo "Glue ETL:"
    echo "  database-create <name>                     - Create Glue database"
    echo "  crawler-create <name> <bucket> <db>        - Create crawler"
    echo "  crawler-run <name>                         - Run crawler"
    echo "  job-create <name> <script> <bucket> <conn> - Create ETL job"
    echo "  job-run <name>                             - Run ETL job"
    echo ""
    echo "Redshift:"
    echo "  cluster-create <id> <db> <user> <pass>     - Create Redshift cluster"
    echo "  cluster-delete <id>                        - Delete cluster"
    echo "  cluster-list                               - List clusters"
    echo "  cluster-describe <id>                      - Describe cluster"
    echo ""
    echo "QuickSight:"
    echo "  qs-datasource-create <name> <cluster-id> <db> <user> <pass> - Create data source"
    echo "  qs-datasource-delete <id>                  - Delete data source"
    echo "  qs-datasource-list                         - List data sources"
    echo "  qs-dataset-create <name> <datasource-id> <table> - Create dataset"
    echo "  qs-dataset-delete <id>                     - Delete dataset"
    echo "  qs-dataset-list                            - List datasets"
    echo "  qs-analysis-create <name> <dataset-id>     - Create analysis"
    echo "  qs-analysis-list                           - List analyses"
    echo "  qs-dashboard-create <name> <analysis-id>   - Create dashboard"
    echo "  qs-dashboard-list                          - List dashboards"
    echo "  qs-user-list                               - List QuickSight users"
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

    aws s3 cp "$file" "s3://$bucket/$prefix/$(basename "$file")"
    log_info "Data uploaded"
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

    log_step "Creating crawler: $name"
    local account_id=$(get_account_id)
    local role_name="${name}-crawler-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket"],"Resource":["arn:aws:s3:::$bucket","arn:aws:s3:::$bucket/*"]}]}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3" --policy-document "$s3_policy"

    sleep 10
    aws glue create-crawler --name "$name" --role "arn:aws:iam::$account_id:role/$role_name" --database-name "$database" --targets "{\"S3Targets\":[{\"Path\":\"s3://$bucket/\"}]}"
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
    local bucket=$3
    local connection=$4

    if [ -z "$name" ] || [ -z "$script" ] || [ -z "$bucket" ] || [ -z "$connection" ]; then
        log_error "Job name, script path, bucket, and connection required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-glue-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true

    sleep 10
    aws glue create-job --name "$name" --role "arn:aws:iam::$account_id:role/$role_name" \
        --command "{\"Name\":\"glueetl\",\"ScriptLocation\":\"$script\",\"PythonVersion\":\"3\"}" \
        --connections "{\"Connections\":[\"$connection\"]}" --glue-version "4.0" --number-of-workers 2 --worker-type "G.1X"
    log_info "Job created"
}

job_run() {
    local name=$1
    [ -z "$name" ] && { log_error "Job name required"; exit 1; }
    aws glue start-job-run --job-name "$name"
    log_info "Job started"
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
    aws redshift create-cluster --cluster-identifier "$id" --node-type dc2.large --number-of-nodes 1 \
        --master-username "$user" --master-user-password "$password" --db-name "$database" --publicly-accessible
    log_info "Cluster creation initiated (5-10 minutes)"
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
    aws redshift describe-clusters --query 'Clusters[].{ID:ClusterIdentifier,Status:ClusterStatus,Endpoint:Endpoint.Address}' --output table
}

cluster_describe() {
    local id=$1
    [ -z "$id" ] && { log_error "Cluster ID required"; exit 1; }
    aws redshift describe-clusters --cluster-identifier "$id" --query 'Clusters[0]' --output json
}

# QuickSight Functions
qs_datasource_create() {
    local name=$1
    local cluster_id=$2
    local database=$3
    local user=$4
    local password=$5

    if [ -z "$name" ] || [ -z "$cluster_id" ] || [ -z "$database" ] || [ -z "$user" ] || [ -z "$password" ]; then
        log_error "Name, cluster ID, database, username, and password required"
        exit 1
    fi

    log_step "Creating QuickSight data source: $name"
    local account_id=$(get_account_id)

    local cluster_info=$(aws redshift describe-clusters --cluster-identifier "$cluster_id" --query 'Clusters[0]')
    local host=$(echo "$cluster_info" | jq -r '.Endpoint.Address')
    local port=$(echo "$cluster_info" | jq -r '.Endpoint.Port')
    local vpc_id=$(echo "$cluster_info" | jq -r '.VpcId')

    aws quicksight create-data-source \
        --aws-account-id "$account_id" \
        --data-source-id "$name" \
        --name "$name" \
        --type REDSHIFT \
        --data-source-parameters "{
            \"RedshiftParameters\": {
                \"Host\": \"$host\",
                \"Port\": $port,
                \"Database\": \"$database\",
                \"ClusterId\": \"$cluster_id\"
            }
        }" \
        --credentials "{
            \"CredentialPair\": {
                \"Username\": \"$user\",
                \"Password\": \"$password\"
            }
        }" \
        --permissions "[{
            \"Principal\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:user/default/Admin\",
            \"Actions\": [
                \"quicksight:UpdateDataSourcePermissions\",
                \"quicksight:DescribeDataSource\",
                \"quicksight:DescribeDataSourcePermissions\",
                \"quicksight:PassDataSource\",
                \"quicksight:UpdateDataSource\",
                \"quicksight:DeleteDataSource\"
            ]
        }]"

    log_info "Data source created"
}

qs_datasource_delete() {
    local id=$1
    [ -z "$id" ] && { log_error "Data source ID required"; exit 1; }
    local account_id=$(get_account_id)
    aws quicksight delete-data-source --aws-account-id "$account_id" --data-source-id "$id"
    log_info "Data source deleted"
}

qs_datasource_list() {
    local account_id=$(get_account_id)
    aws quicksight list-data-sources --aws-account-id "$account_id" --query 'DataSources[].{Name:Name,Type:Type,Status:Status}' --output table
}

qs_dataset_create() {
    local name=$1
    local datasource_id=$2
    local table=$3

    if [ -z "$name" ] || [ -z "$datasource_id" ] || [ -z "$table" ]; then
        log_error "Name, data source ID, and table name required"
        exit 1
    fi

    log_step "Creating QuickSight dataset: $name"
    local account_id=$(get_account_id)

    aws quicksight create-data-set \
        --aws-account-id "$account_id" \
        --data-set-id "$name" \
        --name "$name" \
        --import-mode SPICE \
        --physical-table-map "{
            \"$table\": {
                \"RelationalTable\": {
                    \"DataSourceArn\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:datasource/$datasource_id\",
                    \"Schema\": \"public\",
                    \"Name\": \"$table\",
                    \"InputColumns\": []
                }
            }
        }" \
        --permissions "[{
            \"Principal\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:user/default/Admin\",
            \"Actions\": [
                \"quicksight:UpdateDataSetPermissions\",
                \"quicksight:DescribeDataSet\",
                \"quicksight:DescribeDataSetPermissions\",
                \"quicksight:PassDataSet\",
                \"quicksight:DescribeIngestion\",
                \"quicksight:ListIngestions\",
                \"quicksight:UpdateDataSet\",
                \"quicksight:DeleteDataSet\",
                \"quicksight:CreateIngestion\",
                \"quicksight:CancelIngestion\"
            ]
        }]"

    log_info "Dataset created"
}

qs_dataset_delete() {
    local id=$1
    [ -z "$id" ] && { log_error "Dataset ID required"; exit 1; }
    local account_id=$(get_account_id)
    aws quicksight delete-data-set --aws-account-id "$account_id" --data-set-id "$id"
    log_info "Dataset deleted"
}

qs_dataset_list() {
    local account_id=$(get_account_id)
    aws quicksight list-data-sets --aws-account-id "$account_id" --query 'DataSetSummaries[].{Name:Name,ImportMode:ImportMode}' --output table
}

qs_analysis_create() {
    local name=$1
    local dataset_id=$2

    if [ -z "$name" ] || [ -z "$dataset_id" ]; then
        log_error "Name and dataset ID required"
        exit 1
    fi

    log_step "Creating QuickSight analysis: $name"
    local account_id=$(get_account_id)

    aws quicksight create-analysis \
        --aws-account-id "$account_id" \
        --analysis-id "$name" \
        --name "$name" \
        --source-entity "{
            \"SourceTemplate\": {
                \"DataSetReferences\": [{
                    \"DataSetPlaceholder\": \"MainDataSet\",
                    \"DataSetArn\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:dataset/$dataset_id\"
                }],
                \"Arn\": \"arn:aws:quicksight:us-east-1:aws:template/basic-template\"
            }
        }" \
        --permissions "[{
            \"Principal\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:user/default/Admin\",
            \"Actions\": [
                \"quicksight:RestoreAnalysis\",
                \"quicksight:UpdateAnalysisPermissions\",
                \"quicksight:DeleteAnalysis\",
                \"quicksight:DescribeAnalysisPermissions\",
                \"quicksight:QueryAnalysis\",
                \"quicksight:DescribeAnalysis\",
                \"quicksight:UpdateAnalysis\"
            ]
        }]"

    log_info "Analysis created"
}

qs_analysis_list() {
    local account_id=$(get_account_id)
    aws quicksight list-analyses --aws-account-id "$account_id" --query 'AnalysisSummaryList[].{Name:Name,Status:Status}' --output table
}

qs_dashboard_create() {
    local name=$1
    local analysis_id=$2

    if [ -z "$name" ] || [ -z "$analysis_id" ]; then
        log_error "Name and analysis ID required"
        exit 1
    fi

    log_step "Creating QuickSight dashboard: $name"
    local account_id=$(get_account_id)

    aws quicksight create-dashboard \
        --aws-account-id "$account_id" \
        --dashboard-id "$name" \
        --name "$name" \
        --source-entity "{
            \"SourceAnalysis\": {
                \"Arn\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:analysis/$analysis_id\",
                \"DataSetArns\": []
            }
        }" \
        --permissions "[{
            \"Principal\": \"arn:aws:quicksight:$DEFAULT_REGION:$account_id:user/default/Admin\",
            \"Actions\": [
                \"quicksight:DescribeDashboard\",
                \"quicksight:ListDashboardVersions\",
                \"quicksight:UpdateDashboardPermissions\",
                \"quicksight:QueryDashboard\",
                \"quicksight:UpdateDashboard\",
                \"quicksight:DeleteDashboard\",
                \"quicksight:DescribeDashboardPermissions\",
                \"quicksight:UpdateDashboardPublishedVersion\"
            ]
        }]"

    log_info "Dashboard created"
}

qs_dashboard_list() {
    local account_id=$(get_account_id)
    aws quicksight list-dashboards --aws-account-id "$account_id" --query 'DashboardSummaryList[].{Name:Name,PublishedVersionNumber:PublishedVersionNumber}' --output table
}

qs_user_list() {
    local account_id=$(get_account_id)
    aws quicksight list-users --aws-account-id "$account_id" --namespace default --query 'UserList[].{UserName:UserName,Email:Email,Role:Role}' --output table
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → Glue → Redshift → QuickSight stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-bi-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Create sample sales data
    log_step "Creating sample data..."
    cat << 'EOF' > /tmp/sales_analytics.csv
date,region,product_category,sales_amount,units_sold,customer_segment
2024-01-01,North,Electronics,15000,50,Enterprise
2024-01-01,South,Clothing,8500,120,Consumer
2024-01-01,East,Electronics,12000,40,Enterprise
2024-01-01,West,Home,6500,80,Consumer
2024-01-02,North,Clothing,9200,100,Consumer
2024-01-02,South,Electronics,18000,60,Enterprise
2024-01-02,East,Home,7800,95,Consumer
2024-01-02,West,Electronics,14500,48,Enterprise
2024-01-03,North,Home,5600,70,Consumer
2024-01-03,South,Clothing,11000,150,Consumer
2024-01-03,East,Electronics,16500,55,Enterprise
2024-01-03,West,Clothing,8900,110,Consumer
EOF
    aws s3 cp /tmp/sales_analytics.csv "s3://$bucket_name/input/sales/"

    # Create Glue database
    log_step "Creating Glue database..."
    aws glue create-database --database-input "{\"Name\": \"${name}_bi_db\"}" 2>/dev/null || log_info "Database exists"

    rm -f /tmp/sales_analytics.csv

    echo ""
    echo -e "${GREEN}Partial deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Glue Database: ${name}_bi_db"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo "1. Create Redshift cluster:"
    echo "   $0 cluster-create ${name}-dw warehouse admin YourPass123!"
    echo ""
    echo "2. Wait for cluster, then create Glue connection and run ETL"
    echo ""
    echo "3. Subscribe to QuickSight (if not already):"
    echo "   https://quicksight.aws.amazon.com/"
    echo ""
    echo "4. Create QuickSight data source:"
    echo "   $0 qs-datasource-create ${name}-ds ${name}-dw warehouse admin YourPass123!"
    echo ""
    echo "5. Create dataset, analysis, and dashboard in QuickSight console"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete QuickSight resources
    aws quicksight delete-data-source --aws-account-id "$account_id" --data-source-id "${name}-ds" 2>/dev/null || true

    # Delete Redshift
    aws redshift delete-cluster --cluster-identifier "${name}-dw" --skip-final-cluster-snapshot 2>/dev/null || true

    # Delete Glue
    aws glue delete-database --name "${name}_bi_db" 2>/dev/null || true

    # Delete S3
    local bucket_name="${name}-bi-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    local account_id=$(get_account_id)
    echo -e "${BLUE}=== Redshift Clusters ===${NC}"
    cluster_list
    echo -e "\n${BLUE}=== QuickSight Data Sources ===${NC}"
    qs_datasource_list 2>/dev/null || echo "QuickSight not subscribed or no data sources"
    echo -e "\n${BLUE}=== QuickSight Datasets ===${NC}"
    qs_dataset_list 2>/dev/null || echo "None"
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
    database-create) database_create "$@" ;;
    crawler-create) crawler_create "$@" ;;
    crawler-run) crawler_run "$@" ;;
    job-create) job_create "$@" ;;
    job-run) job_run "$@" ;;
    cluster-create) cluster_create "$@" ;;
    cluster-delete) cluster_delete "$@" ;;
    cluster-list) cluster_list ;;
    cluster-describe) cluster_describe "$@" ;;
    qs-datasource-create) qs_datasource_create "$@" ;;
    qs-datasource-delete) qs_datasource_delete "$@" ;;
    qs-datasource-list) qs_datasource_list ;;
    qs-dataset-create) qs_dataset_create "$@" ;;
    qs-dataset-delete) qs_dataset_delete "$@" ;;
    qs-dataset-list) qs_dataset_list ;;
    qs-analysis-create) qs_analysis_create "$@" ;;
    qs-analysis-list) qs_analysis_list ;;
    qs-dashboard-create) qs_dashboard_create "$@" ;;
    qs-dashboard-list) qs_dashboard_list ;;
    qs-user-list) qs_user_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
