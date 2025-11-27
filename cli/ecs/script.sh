#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ECS Operations Script
# Provides common ECS (Elastic Container Service) operations using AWS CLI

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Cluster Commands:"
    echo "  list-clusters                       - List all ECS clusters"
    echo "  create-cluster <name>               - Create a new ECS cluster"
    echo "  delete-cluster <name>               - Delete an ECS cluster"
    echo "  describe-cluster <name>             - Get cluster details"
    echo ""
    echo "Task Definition Commands:"
    echo "  list-task-definitions               - List all task definitions"
    echo "  register-task-definition <file>     - Register a new task definition"
    echo "  deregister-task-definition <arn>    - Deregister a task definition"
    echo "  describe-task-definition <family:revision> - Get task definition details"
    echo ""
    echo "Service Commands:"
    echo "  list-services <cluster-name>        - List services in a cluster"
    echo "  create-service <cluster> <service> <task-def> <count> - Create a service"
    echo "  delete-service <cluster-name> <service-name> - Delete a service"
    echo "  describe-service <cluster-name> <service-name> - Get service details"
    echo "  update-service <cluster> <service> [--desired-count N] - Update a service"
    echo "  scale-service <cluster> <service> <count> - Scale a service"
    echo ""
    echo "Task Commands:"
    echo "  list-tasks <cluster-name>           - List tasks in a cluster"
    echo "  run-task <cluster> <task-def> [count] - Run a task"
    echo "  stop-task <cluster-name> <task-id>  - Stop a task"
    echo "  describe-task <cluster-name> <task-id> - Get task details"
    echo ""
    echo "Container Instance Commands:"
    echo "  list-container-instances <cluster>  - List container instances"
    echo "  describe-container-instance <cluster> <instance-id> - Get instance details"
    echo ""
    echo "Logs Commands:"
    echo "  get-task-logs <task-family> [minutes] - Get CloudWatch logs for task"
    echo ""
    exit 1
}

# List all ECS clusters
list_clusters() {
    echo -e "${GREEN}Listing all ECS clusters...${NC}"
    aws ecs list-clusters --query 'clusterArns[*]' --output table
}

# Create a new ECS cluster
create_cluster() {
    local cluster_name=$1
    if [ -z "$cluster_name" ]; then
        echo -e "${RED}Error: Cluster name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating ECS cluster: $cluster_name${NC}"
    aws ecs create-cluster --cluster-name "$cluster_name"
    echo -e "${GREEN}Cluster created successfully${NC}"
}

# Delete an ECS cluster
delete_cluster() {
    local cluster_name=$1
    if [ -z "$cluster_name" ]; then
        echo -e "${RED}Error: Cluster name is required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete cluster: $cluster_name${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting ECS cluster: $cluster_name${NC}"
    aws ecs delete-cluster --cluster "$cluster_name"
    echo -e "${GREEN}Cluster deleted successfully${NC}"
}

# Describe cluster
describe_cluster() {
    local cluster_name=$1
    if [ -z "$cluster_name" ]; then
        echo -e "${RED}Error: Cluster name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for cluster: $cluster_name${NC}"
    aws ecs describe-clusters --clusters "$cluster_name"
}

# List all task definitions
list_task_definitions() {
    echo -e "${GREEN}Listing all task definitions...${NC}"
    aws ecs list-task-definitions --query 'taskDefinitionArns[*]' --output table
}

# Register a new task definition
register_task_definition() {
    local file=$1
    if [ -z "$file" ]; then
        echo -e "${RED}Error: Task definition file is required${NC}"
        exit 1
    fi

    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File does not exist: $file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Registering task definition from: $file${NC}"
    aws ecs register-task-definition --cli-input-json "file://$file"
    echo -e "${GREEN}Task definition registered successfully${NC}"
}

# Deregister a task definition
deregister_task_definition() {
    local task_def_arn=$1
    if [ -z "$task_def_arn" ]; then
        echo -e "${RED}Error: Task definition ARN is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Deregistering task definition: $task_def_arn${NC}"
    aws ecs deregister-task-definition --task-definition "$task_def_arn"
    echo -e "${GREEN}Task definition deregistered successfully${NC}"
}

# Describe task definition
describe_task_definition() {
    local task_def=$1
    if [ -z "$task_def" ]; then
        echo -e "${RED}Error: Task definition family:revision is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for task definition: $task_def${NC}"
    aws ecs describe-task-definition --task-definition "$task_def"
}

# List services in a cluster
list_services() {
    local cluster_name=$1
    if [ -z "$cluster_name" ]; then
        echo -e "${RED}Error: Cluster name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing services in cluster: $cluster_name${NC}"
    aws ecs list-services --cluster "$cluster_name" --query 'serviceArns[*]' --output table
}

# Create a service
create_service() {
    local cluster=$1
    local service=$2
    local task_def=$3
    local count=${4:-1}

    if [ -z "$cluster" ] || [ -z "$service" ] || [ -z "$task_def" ]; then
        echo -e "${RED}Error: Cluster, service name, and task definition are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating service: $service in cluster: $cluster${NC}"
    aws ecs create-service \
        --cluster "$cluster" \
        --service-name "$service" \
        --task-definition "$task_def" \
        --desired-count "$count"
    echo -e "${GREEN}Service created successfully${NC}"
}

# Delete a service
delete_service() {
    local cluster=$1
    local service=$2

    if [ -z "$cluster" ] || [ -z "$service" ]; then
        echo -e "${RED}Error: Cluster name and service name are required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete service: $service from cluster: $cluster${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting service: $service${NC}"
    aws ecs delete-service --cluster "$cluster" --service "$service" --force
    echo -e "${GREEN}Service deleted successfully${NC}"
}

# Describe service
describe_service() {
    local cluster=$1
    local service=$2

    if [ -z "$cluster" ] || [ -z "$service" ]; then
        echo -e "${RED}Error: Cluster name and service name are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for service: $service in cluster: $cluster${NC}"
    aws ecs describe-services --cluster "$cluster" --services "$service"
}

# Update service
update_service() {
    local cluster=$1
    local service=$2
    shift 2

    if [ -z "$cluster" ] || [ -z "$service" ]; then
        echo -e "${RED}Error: Cluster name and service name are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Updating service: $service in cluster: $cluster${NC}"
    aws ecs update-service --cluster "$cluster" --service "$service" "$@"
    echo -e "${GREEN}Service updated successfully${NC}"
}

# Scale service
scale_service() {
    local cluster=$1
    local service=$2
    local count=$3

    if [ -z "$cluster" ] || [ -z "$service" ] || [ -z "$count" ]; then
        echo -e "${RED}Error: Cluster name, service name, and desired count are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Scaling service: $service to $count tasks${NC}"
    aws ecs update-service \
        --cluster "$cluster" \
        --service "$service" \
        --desired-count "$count"
    echo -e "${GREEN}Service scaled successfully${NC}"
}

# List tasks in a cluster
list_tasks() {
    local cluster=$1
    if [ -z "$cluster" ]; then
        echo -e "${RED}Error: Cluster name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing tasks in cluster: $cluster${NC}"
    aws ecs list-tasks --cluster "$cluster" --query 'taskArns[*]' --output table
}

# Run a task
run_task() {
    local cluster=$1
    local task_def=$2
    local count=${3:-1}

    if [ -z "$cluster" ] || [ -z "$task_def" ]; then
        echo -e "${RED}Error: Cluster name and task definition are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Running task: $task_def in cluster: $cluster${NC}"
    aws ecs run-task \
        --cluster "$cluster" \
        --task-definition "$task_def" \
        --count "$count"
    echo -e "${GREEN}Task started successfully${NC}"
}

# Stop a task
stop_task() {
    local cluster=$1
    local task_id=$2

    if [ -z "$cluster" ] || [ -z "$task_id" ]; then
        echo -e "${RED}Error: Cluster name and task ID are required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will stop task: $task_id${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Stopping task: $task_id${NC}"
    aws ecs stop-task --cluster "$cluster" --task "$task_id"
    echo -e "${GREEN}Task stopped successfully${NC}"
}

# Describe task
describe_task() {
    local cluster=$1
    local task_id=$2

    if [ -z "$cluster" ] || [ -z "$task_id" ]; then
        echo -e "${RED}Error: Cluster name and task ID are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for task: $task_id${NC}"
    aws ecs describe-tasks --cluster "$cluster" --tasks "$task_id"
}

# List container instances
list_container_instances() {
    local cluster=$1
    if [ -z "$cluster" ]; then
        echo -e "${RED}Error: Cluster name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing container instances in cluster: $cluster${NC}"
    aws ecs list-container-instances --cluster "$cluster" --query 'containerInstanceArns[*]' --output table
}

# Describe container instance
describe_container_instance() {
    local cluster=$1
    local instance_id=$2

    if [ -z "$cluster" ] || [ -z "$instance_id" ]; then
        echo -e "${RED}Error: Cluster name and instance ID are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for container instance: $instance_id${NC}"
    aws ecs describe-container-instances --cluster "$cluster" --container-instances "$instance_id"
}

# Get task logs from CloudWatch
get_task_logs() {
    local task_family=$1
    local minutes=${2:-10}

    if [ -z "$task_family" ]; then
        echo -e "${RED}Error: Task family name is required${NC}"
        exit 1
    fi

    local log_group="/ecs/$task_family"

    echo -e "${GREEN}Getting logs for task family: $task_family (last $minutes minutes)${NC}"
    aws logs tail "$log_group" --since "${minutes}m" --follow=false
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    list-clusters)
        list_clusters
        ;;
    create-cluster)
        create_cluster "$@"
        ;;
    delete-cluster)
        delete_cluster "$@"
        ;;
    describe-cluster)
        describe_cluster "$@"
        ;;
    list-task-definitions)
        list_task_definitions
        ;;
    register-task-definition)
        register_task_definition "$@"
        ;;
    deregister-task-definition)
        deregister_task_definition "$@"
        ;;
    describe-task-definition)
        describe_task_definition "$@"
        ;;
    list-services)
        list_services "$@"
        ;;
    create-service)
        create_service "$@"
        ;;
    delete-service)
        delete_service "$@"
        ;;
    describe-service)
        describe_service "$@"
        ;;
    update-service)
        update_service "$@"
        ;;
    scale-service)
        scale_service "$@"
        ;;
    list-tasks)
        list_tasks "$@"
        ;;
    run-task)
        run_task "$@"
        ;;
    stop-task)
        stop_task "$@"
        ;;
    describe-task)
        describe_task "$@"
        ;;
    list-container-instances)
        list_container_instances "$@"
        ;;
    describe-container-instance)
        describe_container_instance "$@"
        ;;
    get-task-logs)
        get_task_logs "$@"
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac
