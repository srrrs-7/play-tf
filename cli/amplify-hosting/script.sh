#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Amplify Hosting Architecture Script
# Provides operations for full-stack web app hosting

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "AWS Amplify Hosting Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <name> <repo-url>             - Deploy Amplify app from repository"
    echo "  destroy <app-id>                     - Destroy Amplify app"
    echo "  status                               - Show status of all apps"
    echo ""
    echo "Amplify App Commands:"
    echo "  app-create <name>                    - Create Amplify app"
    echo "  app-create-repo <name> <repo-url> <token> - Create app connected to repository"
    echo "  app-delete <app-id>                  - Delete Amplify app"
    echo "  app-list                             - List Amplify apps"
    echo "  app-status <app-id>                  - Show app details"
    echo ""
    echo "Branch Commands:"
    echo "  branch-create <app-id> <branch-name> - Create branch"
    echo "  branch-delete <app-id> <branch-name> - Delete branch"
    echo "  branch-list <app-id>                 - List branches"
    echo ""
    echo "Deployment Commands:"
    echo "  deploy-start <app-id> <branch>       - Start deployment"
    echo "  deploy-stop <app-id> <branch> <job-id> - Stop deployment"
    echo "  deploy-list <app-id> <branch>        - List deployments"
    echo "  deploy-manual <app-id> <branch> <zip-file> - Manual deployment from zip"
    echo ""
    echo "Domain Commands:"
    echo "  domain-create <app-id> <domain>      - Add custom domain"
    echo "  domain-delete <app-id> <domain>      - Remove custom domain"
    echo "  domain-list <app-id>                 - List domains"
    echo ""
    echo "Environment Commands:"
    echo "  env-set <app-id> <key> <value>       - Set environment variable"
    echo "  env-delete <app-id> <key>            - Delete environment variable"
    echo "  env-list <app-id>                    - List environment variables"
    echo ""
    echo "Webhook Commands:"
    echo "  webhook-create <app-id> <branch>     - Create webhook for branch"
    echo "  webhook-delete <webhook-id>          - Delete webhook"
    echo "  webhook-list <app-id>                - List webhooks"
    echo ""
    exit 1
}

# ============================================
# Amplify App Functions
# ============================================

app_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "App name is required"
        exit 1
    fi

    log_step "Creating Amplify app: $name"

    local app_id
    app_id=$(aws amplify create-app \
        --name "$name" \
        --query 'app.appId' --output text)

    log_info "App created: $app_id"
    echo ""
    echo "App ID: $app_id"
    echo ""
    echo "Next steps:"
    echo "  1. Connect a repository or deploy manually"
    echo "  2. Create a branch: ./script.sh branch-create $app_id main"
}

app_create_repo() {
    local name=$1
    local repo_url=$2
    local token=$3

    if [ -z "$name" ] || [ -z "$repo_url" ]; then
        log_error "App name and repository URL are required"
        exit 1
    fi

    log_step "Creating Amplify app from repository: $name"

    local app_args="--name $name --repository $repo_url"

    if [ -n "$token" ]; then
        app_args="$app_args --access-token $token"
    fi

    # Build spec for common frameworks
    local build_spec='version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: build
    files:
      - "**/*"
  cache:
    paths:
      - node_modules/**/*'

    local app_id
    app_id=$(aws amplify create-app \
        $app_args \
        --build-spec "$build_spec" \
        --enable-auto-branch-creation \
        --auto-branch-creation-patterns '["main", "dev", "feature/*"]' \
        --query 'app.appId' --output text)

    log_info "App created: $app_id"

    # Get default domain
    local default_domain
    default_domain=$(aws amplify get-app --app-id "$app_id" --query 'app.defaultDomain' --output text)

    echo ""
    echo "App ID: $app_id"
    echo "Default Domain: https://main.$default_domain"
}

app_delete() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    log_warn "This will delete Amplify app: $app_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting Amplify app"
    aws amplify delete-app --app-id "$app_id"
    log_info "App deleted"
}

app_list() {
    log_info "Listing Amplify apps..."
    aws amplify list-apps \
        --query 'apps[].{Name:name,AppId:appId,DefaultDomain:defaultDomain,Repository:repository}' \
        --output table
}

app_status() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    log_info "App status:"
    aws amplify get-app \
        --app-id "$app_id" \
        --query 'app.{Name:name,AppId:appId,DefaultDomain:defaultDomain,Repository:repository,ProductionBranch:productionBranch.branchName}' \
        --output table

    echo ""
    log_info "Branches:"
    branch_list "$app_id"
}

# ============================================
# Branch Functions
# ============================================

branch_create() {
    local app_id=$1
    local branch_name=$2

    if [ -z "$app_id" ] || [ -z "$branch_name" ]; then
        log_error "App ID and branch name are required"
        exit 1
    fi

    log_step "Creating branch: $branch_name"

    aws amplify create-branch \
        --app-id "$app_id" \
        --branch-name "$branch_name" \
        --enable-auto-build

    log_info "Branch created"

    # Get branch URL
    local default_domain
    default_domain=$(aws amplify get-app --app-id "$app_id" --query 'app.defaultDomain' --output text)

    echo "Branch URL: https://$branch_name.$default_domain"
}

branch_delete() {
    local app_id=$1
    local branch_name=$2

    if [ -z "$app_id" ] || [ -z "$branch_name" ]; then
        log_error "App ID and branch name are required"
        exit 1
    fi

    log_warn "This will delete branch: $branch_name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 0
    fi

    aws amplify delete-branch --app-id "$app_id" --branch-name "$branch_name"
    log_info "Branch deleted"
}

branch_list() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    aws amplify list-branches \
        --app-id "$app_id" \
        --query 'branches[].{Branch:branchName,Stage:stage,DisplayName:displayName,LastDeployTime:updateTime}' \
        --output table
}

# ============================================
# Deployment Functions
# ============================================

deploy_start() {
    local app_id=$1
    local branch=$2

    if [ -z "$app_id" ] || [ -z "$branch" ]; then
        log_error "App ID and branch are required"
        exit 1
    fi

    log_step "Starting deployment for branch: $branch"

    local job_id
    job_id=$(aws amplify start-job \
        --app-id "$app_id" \
        --branch-name "$branch" \
        --job-type RELEASE \
        --query 'jobSummary.jobId' --output text)

    log_info "Deployment started: $job_id"
}

deploy_stop() {
    local app_id=$1
    local branch=$2
    local job_id=$3

    if [ -z "$app_id" ] || [ -z "$branch" ] || [ -z "$job_id" ]; then
        log_error "App ID, branch, and job ID are required"
        exit 1
    fi

    aws amplify stop-job --app-id "$app_id" --branch-name "$branch" --job-id "$job_id"
    log_info "Deployment stopped"
}

deploy_list() {
    local app_id=$1
    local branch=$2

    if [ -z "$app_id" ] || [ -z "$branch" ]; then
        log_error "App ID and branch are required"
        exit 1
    fi

    aws amplify list-jobs \
        --app-id "$app_id" \
        --branch-name "$branch" \
        --query 'jobSummaries[].{JobId:jobId,Status:status,StartTime:startTime,EndTime:endTime}' \
        --output table
}

deploy_manual() {
    local app_id=$1
    local branch=$2
    local zip_file=$3

    if [ -z "$app_id" ] || [ -z "$branch" ] || [ -z "$zip_file" ]; then
        log_error "App ID, branch, and zip file are required"
        exit 1
    fi

    if [ ! -f "$zip_file" ]; then
        log_error "Zip file does not exist: $zip_file"
        exit 1
    fi

    log_step "Creating manual deployment"

    # Create deployment
    local deployment
    deployment=$(aws amplify create-deployment \
        --app-id "$app_id" \
        --branch-name "$branch")

    local job_id
    job_id=$(echo "$deployment" | jq -r '.jobId')

    local zip_url
    zip_url=$(echo "$deployment" | jq -r '.zipUploadUrl')

    # Upload zip
    log_info "Uploading deployment package..."
    curl -s -X PUT -T "$zip_file" "$zip_url" -H "Content-Type: application/zip"

    # Start deployment
    aws amplify start-deployment \
        --app-id "$app_id" \
        --branch-name "$branch" \
        --job-id "$job_id"

    log_info "Deployment started: $job_id"
}

# ============================================
# Domain Functions
# ============================================

domain_create() {
    local app_id=$1
    local domain=$2

    if [ -z "$app_id" ] || [ -z "$domain" ]; then
        log_error "App ID and domain are required"
        exit 1
    fi

    log_step "Adding custom domain: $domain"

    aws amplify create-domain-association \
        --app-id "$app_id" \
        --domain-name "$domain" \
        --sub-domain-settings prefix=,branchName=main

    log_info "Domain added. Configure DNS as instructed."
    log_info "Use 'domain-list $app_id' to see DNS configuration"
}

domain_delete() {
    local app_id=$1
    local domain=$2

    if [ -z "$app_id" ] || [ -z "$domain" ]; then
        log_error "App ID and domain are required"
        exit 1
    fi

    aws amplify delete-domain-association --app-id "$app_id" --domain-name "$domain"
    log_info "Domain removed"
}

domain_list() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    aws amplify list-domain-associations \
        --app-id "$app_id" \
        --query 'domainAssociations[].{Domain:domainName,Status:domainStatus,CertVerification:certificateVerificationDNSRecord}' \
        --output table
}

# ============================================
# Environment Variables Functions
# ============================================

env_set() {
    local app_id=$1
    local key=$2
    local value=$3

    if [ -z "$app_id" ] || [ -z "$key" ] || [ -z "$value" ]; then
        log_error "App ID, key, and value are required"
        exit 1
    fi

    log_step "Setting environment variable: $key"

    # Get current env vars
    local current_vars
    current_vars=$(aws amplify get-app --app-id "$app_id" --query 'app.environmentVariables' --output json)

    # Add new var
    local new_vars
    new_vars=$(echo "$current_vars" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')

    aws amplify update-app \
        --app-id "$app_id" \
        --environment-variables "$new_vars"

    log_info "Environment variable set"
}

env_delete() {
    local app_id=$1
    local key=$2

    if [ -z "$app_id" ] || [ -z "$key" ]; then
        log_error "App ID and key are required"
        exit 1
    fi

    local current_vars
    current_vars=$(aws amplify get-app --app-id "$app_id" --query 'app.environmentVariables' --output json)

    local new_vars
    new_vars=$(echo "$current_vars" | jq --arg k "$key" 'del(.[$k])')

    aws amplify update-app \
        --app-id "$app_id" \
        --environment-variables "$new_vars"

    log_info "Environment variable deleted"
}

env_list() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    aws amplify get-app \
        --app-id "$app_id" \
        --query 'app.environmentVariables' \
        --output table
}

# ============================================
# Webhook Functions
# ============================================

webhook_create() {
    local app_id=$1
    local branch=$2

    if [ -z "$app_id" ] || [ -z "$branch" ]; then
        log_error "App ID and branch are required"
        exit 1
    fi

    log_step "Creating webhook for branch: $branch"

    local webhook
    webhook=$(aws amplify create-webhook \
        --app-id "$app_id" \
        --branch-name "$branch")

    local webhook_id
    webhook_id=$(echo "$webhook" | jq -r '.webhook.webhookId')

    local webhook_url
    webhook_url=$(echo "$webhook" | jq -r '.webhook.webhookUrl')

    log_info "Webhook created"
    echo "Webhook ID: $webhook_id"
    echo "Webhook URL: $webhook_url"
}

webhook_delete() {
    local webhook_id=$1

    if [ -z "$webhook_id" ]; then
        log_error "Webhook ID is required"
        exit 1
    fi

    aws amplify delete-webhook --webhook-id "$webhook_id"
    log_info "Webhook deleted"
}

webhook_list() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    aws amplify list-webhooks \
        --app-id "$app_id" \
        --query 'webhooks[].{WebhookId:webhookId,BranchName:branchName,WebhookUrl:webhookUrl}' \
        --output table
}

# ============================================
# Full Stack
# ============================================

deploy() {
    local name=$1
    local repo_url=$2

    if [ -z "$name" ]; then
        log_error "App name is required"
        exit 1
    fi

    log_info "Deploying Amplify app: $name"

    if [ -n "$repo_url" ]; then
        log_warn "For repository connection, you need a personal access token"
        read -p "Enter access token (or press Enter to skip): " token
        app_create_repo "$name" "$repo_url" "$token"
    else
        app_create "$name"
        echo ""
        echo "To connect a repository later, use:"
        echo "  aws amplify update-app --app-id <app-id> --repository <repo-url>"
    fi
}

destroy() {
    local app_id=$1

    if [ -z "$app_id" ]; then
        log_error "App ID is required"
        exit 1
    fi

    app_delete "$app_id"
}

status() {
    log_info "Listing all Amplify apps..."
    app_list
}

# Main
check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status "$@" ;;
    app-create) app_create "$@" ;;
    app-create-repo) app_create_repo "$@" ;;
    app-delete) app_delete "$@" ;;
    app-list) app_list ;;
    app-status) app_status "$@" ;;
    branch-create) branch_create "$@" ;;
    branch-delete) branch_delete "$@" ;;
    branch-list) branch_list "$@" ;;
    deploy-start) deploy_start "$@" ;;
    deploy-stop) deploy_stop "$@" ;;
    deploy-list) deploy_list "$@" ;;
    deploy-manual) deploy_manual "$@" ;;
    domain-create) domain_create "$@" ;;
    domain-delete) domain_delete "$@" ;;
    domain-list) domain_list "$@" ;;
    env-set) env_set "$@" ;;
    env-delete) env_delete "$@" ;;
    env-list) env_list "$@" ;;
    webhook-create) webhook_create "$@" ;;
    webhook-delete) webhook_delete "$@" ;;
    webhook-list) webhook_list "$@" ;;
    *) log_error "Unknown command: $COMMAND"; usage ;;
esac
