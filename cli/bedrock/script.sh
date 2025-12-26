#!/bin/bash
# =============================================================================
# Amazon Bedrock CLI Script
# =============================================================================
# This script provides operations for Amazon Bedrock:
#   - Foundation Model invocation (Claude, Titan, Stable Diffusion, etc.)
#   - Knowledge Base (RAG) management
#   - Embeddings generation
#   - Model access management
#
# Usage: ./script.sh <command> [options]
# =============================================================================

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# =============================================================================
# Default Configuration
# =============================================================================
DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
DEFAULT_MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"
DEFAULT_EMBEDDING_MODEL="amazon.titan-embed-text-v2:0"
DEFAULT_IMAGE_MODEL="stability.stable-diffusion-xl-v1"

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Amazon Bedrock CLI"
    echo ""
    echo "Commands:"
    echo ""
    echo "  === Full Stack ==="
    echo "  deploy <stack-name>                    - Deploy Bedrock + Knowledge Base stack"
    echo "  destroy <stack-name>                   - Destroy all resources"
    echo "  status [stack-name]                    - Show status of all components"
    echo ""
    echo "  === Model Management ==="
    echo "  models                                 - List all foundation models"
    echo "  models-text                            - List text generation models"
    echo "  models-image                           - List image generation models"
    echo "  models-embedding                       - List embedding models"
    echo "  model-access                           - Check model access status"
    echo "  model-info <model-id>                  - Get model details"
    echo ""
    echo "  === Text Generation ==="
    echo "  invoke <prompt> [model-id]             - Invoke text model"
    echo "  chat <prompt> [model-id]               - Chat with Claude model"
    echo "  titan <prompt>                         - Invoke Amazon Titan"
    echo ""
    echo "  === Image Generation ==="
    echo "  image <prompt> [output-file]           - Generate image (Stable Diffusion)"
    echo "  titan-image <prompt> [output-file]     - Generate image (Titan Image)"
    echo ""
    echo "  === Embeddings ==="
    echo "  embed <text> [model-id]                - Generate embeddings"
    echo "  embed-file <file> [model-id]           - Generate embeddings from file"
    echo ""
    echo "  === Knowledge Base (RAG) ==="
    echo "  kb-create <name> <bucket> [model-id]   - Create Knowledge Base"
    echo "  kb-list                                - List Knowledge Bases"
    echo "  kb-show <kb-id>                        - Show Knowledge Base details"
    echo "  kb-delete <kb-id>                      - Delete Knowledge Base"
    echo "  kb-sync <kb-id> <datasource-id>        - Sync data source"
    echo "  kb-query <kb-id> <query> [model-id]    - Query Knowledge Base"
    echo ""
    echo "  === Data Sources ==="
    echo "  ds-create <kb-id> <bucket>             - Create S3 data source"
    echo "  ds-list <kb-id>                        - List data sources"
    echo "  ds-delete <kb-id> <ds-id>              - Delete data source"
    echo ""
    echo "  === S3 Document Storage ==="
    echo "  bucket-create <name>                   - Create S3 bucket for documents"
    echo "  bucket-delete <name>                   - Delete bucket"
    echo "  upload <bucket> <file>                 - Upload document"
    echo "  upload-dir <bucket> <dir>              - Upload directory"
    echo "  list <bucket> [prefix]                 - List documents"
    echo ""
    echo "Examples:"
    echo "  # Deploy full RAG stack"
    echo "  $0 deploy my-rag-app"
    echo ""
    echo "  # Simple text generation"
    echo "  $0 chat 'Explain quantum computing in simple terms'"
    echo ""
    echo "  # Image generation"
    echo "  $0 image 'A beautiful sunset over mountains' sunset.png"
    echo ""
    echo "  # Query Knowledge Base"
    echo "  $0 kb-query kb-xxxxxxxx 'What is the refund policy?'"
    echo ""
    exit 1
}

# =============================================================================
# Model Management Functions
# =============================================================================
models() {
    log_step "Listing all foundation models..."
    aws bedrock list-foundation-models \
        --query 'modelSummaries[].{ModelId:modelId,Provider:providerName,Name:modelName,Modality:outputModalities[0]}' \
        --output table 2>/dev/null || log_error "Bedrock not available or no access"
}

models_text() {
    log_step "Listing text generation models..."
    aws bedrock list-foundation-models \
        --by-output-modality TEXT \
        --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ModelId:modelId,Provider:providerName,Name:modelName}' \
        --output table 2>/dev/null || log_error "Bedrock not available or no access"
}

models_image() {
    log_step "Listing image generation models..."
    aws bedrock list-foundation-models \
        --by-output-modality IMAGE \
        --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ModelId:modelId,Provider:providerName,Name:modelName}' \
        --output table 2>/dev/null || log_error "Bedrock not available or no access"
}

models_embedding() {
    log_step "Listing embedding models..."
    aws bedrock list-foundation-models \
        --by-output-modality EMBEDDING \
        --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ModelId:modelId,Provider:providerName,Name:modelName}' \
        --output table 2>/dev/null || log_error "Bedrock not available or no access"
}

model_access() {
    log_step "Checking model access status..."
    echo ""
    echo -e "${YELLOW}To enable model access:${NC}"
    echo "1. Go to AWS Console -> Bedrock -> Model access"
    echo "2. Request access for desired models"
    echo "3. Wait for approval (usually immediate for most models)"
    echo ""
    echo -e "${BLUE}=== Available Models ===${NC}"
    aws bedrock list-foundation-models \
        --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ModelId:modelId,Provider:providerName}' \
        --output table 2>/dev/null || log_warn "Unable to check model access"
}

model_info() {
    local model_id=$1
    require_param "$model_id" "Model ID"

    log_step "Getting model info: $model_id"
    aws bedrock get-foundation-model --model-identifier "$model_id" --output yaml
}

# =============================================================================
# Text Generation Functions
# =============================================================================
invoke_model() {
    local prompt=$1
    local model_id=${2:-$DEFAULT_MODEL_ID}

    require_param "$prompt" "Prompt"

    log_step "Invoking model: $model_id"

    local body
    local response_path

    if [[ "$model_id" == *"anthropic"* ]]; then
        body=$(jq -n \
            --arg prompt "$prompt" \
            '{
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 2048,
                "messages": [{"role": "user", "content": $prompt}]
            }')
        response_path=".content[0].text"
    elif [[ "$model_id" == *"amazon.titan-text"* ]]; then
        body=$(jq -n \
            --arg prompt "$prompt" \
            '{
                "inputText": $prompt,
                "textGenerationConfig": {
                    "maxTokenCount": 2048,
                    "temperature": 0.7,
                    "topP": 0.9
                }
            }')
        response_path=".results[0].outputText"
    elif [[ "$model_id" == *"meta.llama"* ]]; then
        body=$(jq -n \
            --arg prompt "$prompt" \
            '{
                "prompt": $prompt,
                "max_gen_len": 2048,
                "temperature": 0.7,
                "top_p": 0.9
            }')
        response_path=".generation"
    elif [[ "$model_id" == *"mistral"* ]]; then
        body=$(jq -n \
            --arg prompt "$prompt" \
            '{
                "prompt": ("<s>[INST] " + $prompt + " [/INST]"),
                "max_tokens": 2048,
                "temperature": 0.7
            }')
        response_path=".outputs[0].text"
    else
        body=$(jq -n \
            --arg prompt "$prompt" \
            '{
                "prompt": $prompt,
                "max_tokens": 2048
            }')
        response_path=".completion // .generation // .results[0].outputText"
    fi

    local output_file=$(mktemp)

    aws bedrock-runtime invoke-model \
        --model-id "$model_id" \
        --body "$(echo "$body" | base64)" \
        --content-type "application/json" \
        --accept "application/json" \
        "$output_file" > /dev/null

    echo ""
    echo -e "${GREEN}=== Response ===${NC}"
    cat "$output_file" | jq -r "$response_path"
    rm -f "$output_file"
}

chat() {
    local prompt=$1
    local model_id=${2:-"anthropic.claude-3-haiku-20240307-v1:0"}

    require_param "$prompt" "Prompt"

    log_step "Chatting with Claude..."

    local body=$(jq -n \
        --arg prompt "$prompt" \
        '{
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "messages": [{"role": "user", "content": $prompt}]
        }')

    local output_file=$(mktemp)

    aws bedrock-runtime invoke-model \
        --model-id "$model_id" \
        --body "$(echo "$body" | base64)" \
        --content-type "application/json" \
        --accept "application/json" \
        "$output_file" > /dev/null

    echo ""
    cat "$output_file" | jq -r '.content[0].text'
    rm -f "$output_file"
}

titan() {
    local prompt=$1
    require_param "$prompt" "Prompt"

    invoke_model "$prompt" "amazon.titan-text-express-v1"
}

# =============================================================================
# Image Generation Functions
# =============================================================================
image() {
    local prompt=$1
    local output_file=${2:-"generated-image.png"}

    require_param "$prompt" "Prompt"

    log_step "Generating image with Stable Diffusion..."

    local body=$(jq -n \
        --arg prompt "$prompt" \
        '{
            "text_prompts": [{"text": $prompt, "weight": 1}],
            "cfg_scale": 7,
            "steps": 50,
            "seed": 0,
            "width": 1024,
            "height": 1024
        }')

    local temp_file=$(mktemp)

    aws bedrock-runtime invoke-model \
        --model-id "$DEFAULT_IMAGE_MODEL" \
        --body "$(echo "$body" | base64)" \
        --content-type "application/json" \
        --accept "application/json" \
        "$temp_file" > /dev/null

    # Extract base64 image and decode
    cat "$temp_file" | jq -r '.artifacts[0].base64' | base64 -d > "$output_file"
    rm -f "$temp_file"

    log_success "Image saved to: $output_file"
}

titan_image() {
    local prompt=$1
    local output_file=${2:-"generated-image.png"}

    require_param "$prompt" "Prompt"

    log_step "Generating image with Amazon Titan..."

    local body=$(jq -n \
        --arg prompt "$prompt" \
        '{
            "taskType": "TEXT_IMAGE",
            "textToImageParams": {
                "text": $prompt
            },
            "imageGenerationConfig": {
                "numberOfImages": 1,
                "height": 1024,
                "width": 1024,
                "cfgScale": 8.0
            }
        }')

    local temp_file=$(mktemp)

    aws bedrock-runtime invoke-model \
        --model-id "amazon.titan-image-generator-v1" \
        --body "$(echo "$body" | base64)" \
        --content-type "application/json" \
        --accept "application/json" \
        "$temp_file" > /dev/null

    cat "$temp_file" | jq -r '.images[0]' | base64 -d > "$output_file"
    rm -f "$temp_file"

    log_success "Image saved to: $output_file"
}

# =============================================================================
# Embeddings Functions
# =============================================================================
embed() {
    local text=$1
    local model_id=${2:-$DEFAULT_EMBEDDING_MODEL}

    require_param "$text" "Text"

    log_step "Generating embeddings..."

    local body
    if [[ "$model_id" == *"titan-embed-text-v2"* ]]; then
        body=$(jq -n --arg text "$text" '{"inputText": $text}')
    elif [[ "$model_id" == *"cohere"* ]]; then
        body=$(jq -n --arg text "$text" '{"texts": [$text], "input_type": "search_document"}')
    else
        body=$(jq -n --arg text "$text" '{"inputText": $text}')
    fi

    local output_file=$(mktemp)

    aws bedrock-runtime invoke-model \
        --model-id "$model_id" \
        --body "$(echo "$body" | base64)" \
        --content-type "application/json" \
        --accept "application/json" \
        "$output_file" > /dev/null

    local dims=$(cat "$output_file" | jq '.embedding | length')
    echo ""
    echo -e "${GREEN}Embedding generated${NC}"
    echo "Dimensions: $dims"
    echo "First 5 values: $(cat "$output_file" | jq '.embedding[0:5]')"

    rm -f "$output_file"
}

embed_file() {
    local file=$1
    local model_id=${2:-$DEFAULT_EMBEDDING_MODEL}

    require_file "$file" "Input file"

    local text=$(cat "$file")
    embed "$text" "$model_id"
}

# =============================================================================
# Knowledge Base Functions
# =============================================================================
kb_create() {
    local name=$1
    local bucket=$2
    local embedding_model=${3:-$DEFAULT_EMBEDDING_MODEL}

    require_param "$name" "Knowledge Base name"
    require_param "$bucket" "S3 bucket name"

    log_step "Creating Knowledge Base: $name"

    local account_id=$(get_account_id)
    local region=$(get_region)

    # Create IAM role for Knowledge Base
    log_info "Creating IAM role..."
    local role_name="${name}-kb-role"
    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "bedrock.amazonaws.com"},
        "Action": "sts:AssumeRole",
        "Condition": {
            "StringEquals": {"aws:SourceAccount": "$account_id"},
            "ArnLike": {"aws:SourceArn": "arn:aws:bedrock:$region:$account_id:knowledge-base/*"}
        }
    }]
}
EOF
)

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || log_info "Role already exists"

    # Attach policies
    local kb_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["bedrock:InvokeModel"],
            "Resource": "arn:aws:bedrock:$region::foundation-model/$embedding_model"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:ListBucket"],
            "Resource": ["arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*"]
        }
    ]
}
EOF
)
    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "${name}-kb-policy" \
        --policy-document "$kb_policy"

    sleep 10

    # Create Knowledge Base with OpenSearch Serverless
    log_info "Creating Knowledge Base..."

    # Note: For production, use OpenSearch Serverless. For simplicity, using default vector store.
    local kb_config=$(cat << EOF
{
    "name": "$name",
    "roleArn": "arn:aws:iam::$account_id:role/$role_name",
    "knowledgeBaseConfiguration": {
        "type": "VECTOR",
        "vectorKnowledgeBaseConfiguration": {
            "embeddingModelArn": "arn:aws:bedrock:$region::foundation-model/$embedding_model"
        }
    },
    "storageConfiguration": {
        "type": "OPENSEARCH_SERVERLESS",
        "opensearchServerlessConfiguration": {
            "collectionArn": "PLACEHOLDER",
            "vectorIndexName": "$name-index",
            "fieldMapping": {
                "vectorField": "vector",
                "textField": "text",
                "metadataField": "metadata"
            }
        }
    }
}
EOF
)

    echo ""
    echo -e "${YELLOW}NOTE: Knowledge Base creation requires OpenSearch Serverless collection.${NC}"
    echo ""
    echo "For a simpler setup, use the 'deploy' command which creates all required resources."
    echo ""
    echo "Manual steps:"
    echo "1. Create OpenSearch Serverless collection in AWS Console"
    echo "2. Create vector index"
    echo "3. Create Knowledge Base with the collection ARN"
    echo ""
    echo "Or use Bedrock Console for guided setup:"
    echo "  https://$region.console.aws.amazon.com/bedrock/home?region=$region#/knowledge-bases"
}

kb_list() {
    log_step "Listing Knowledge Bases..."
    aws bedrock-agent list-knowledge-bases \
        --query 'knowledgeBaseSummaries[].{Id:knowledgeBaseId,Name:name,Status:status,UpdatedAt:updatedAt}' \
        --output table 2>/dev/null || log_warn "No Knowledge Bases found or no access"
}

kb_show() {
    local kb_id=$1
    require_param "$kb_id" "Knowledge Base ID"

    log_step "Showing Knowledge Base: $kb_id"
    aws bedrock-agent get-knowledge-base --knowledge-base-id "$kb_id" --output yaml
}

kb_delete() {
    local kb_id=$1
    require_param "$kb_id" "Knowledge Base ID"

    confirm_action "This will delete Knowledge Base: $kb_id"

    log_step "Deleting Knowledge Base: $kb_id"
    aws bedrock-agent delete-knowledge-base --knowledge-base-id "$kb_id"
    log_success "Deleted Knowledge Base: $kb_id"
}

kb_sync() {
    local kb_id=$1
    local ds_id=$2

    require_param "$kb_id" "Knowledge Base ID"
    require_param "$ds_id" "Data Source ID"

    log_step "Starting ingestion job..."
    aws bedrock-agent start-ingestion-job \
        --knowledge-base-id "$kb_id" \
        --data-source-id "$ds_id" \
        --query 'ingestionJob.{JobId:ingestionJobId,Status:status}' \
        --output table

    log_info "Ingestion job started. Use 'kb-show' to check status."
}

kb_query() {
    local kb_id=$1
    local query=$2
    local model_id=${3:-"anthropic.claude-3-haiku-20240307-v1:0"}

    require_param "$kb_id" "Knowledge Base ID"
    require_param "$query" "Query"

    log_step "Querying Knowledge Base..."

    local response=$(aws bedrock-agent-runtime retrieve-and-generate \
        --input "{\"text\": \"$query\"}" \
        --retrieve-and-generate-configuration "{
            \"type\": \"KNOWLEDGE_BASE\",
            \"knowledgeBaseConfiguration\": {
                \"knowledgeBaseId\": \"$kb_id\",
                \"modelArn\": \"arn:aws:bedrock:$(get_region)::foundation-model/$model_id\"
            }
        }" \
        --output json)

    echo ""
    echo -e "${GREEN}=== Answer ===${NC}"
    echo "$response" | jq -r '.output.text'

    echo ""
    echo -e "${BLUE}=== Sources ===${NC}"
    echo "$response" | jq -r '.citations[].retrievedReferences[].location.s3Location.uri // "No sources"'
}

# =============================================================================
# Data Source Functions
# =============================================================================
ds_create() {
    local kb_id=$1
    local bucket=$2

    require_param "$kb_id" "Knowledge Base ID"
    require_param "$bucket" "S3 bucket name"

    log_step "Creating data source for bucket: $bucket"

    aws bedrock-agent create-data-source \
        --knowledge-base-id "$kb_id" \
        --name "${bucket}-datasource" \
        --data-source-configuration "{
            \"type\": \"S3\",
            \"s3Configuration\": {
                \"bucketArn\": \"arn:aws:s3:::$bucket\"
            }
        }" \
        --query 'dataSource.{Id:dataSourceId,Name:name,Status:status}' \
        --output table

    log_success "Data source created"
}

ds_list() {
    local kb_id=$1
    require_param "$kb_id" "Knowledge Base ID"

    log_step "Listing data sources..."
    aws bedrock-agent list-data-sources \
        --knowledge-base-id "$kb_id" \
        --query 'dataSourceSummaries[].{Id:dataSourceId,Name:name,Status:status}' \
        --output table
}

ds_delete() {
    local kb_id=$1
    local ds_id=$2

    require_param "$kb_id" "Knowledge Base ID"
    require_param "$ds_id" "Data Source ID"

    confirm_action "This will delete data source: $ds_id"

    log_step "Deleting data source..."
    aws bedrock-agent delete-data-source \
        --knowledge-base-id "$kb_id" \
        --data-source-id "$ds_id"
    log_success "Deleted data source"
}

# =============================================================================
# S3 Functions
# =============================================================================
bucket_create() {
    local name=$1
    require_param "$name" "Bucket name"

    log_step "Creating S3 bucket: $name"

    local region=$(get_region)
    if [ "$region" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket \
            --bucket "$name" \
            --region "$region" \
            --create-bucket-configuration LocationConstraint="$region"
    fi

    log_success "Bucket created: $name"
}

bucket_delete() {
    local name=$1
    require_param "$name" "Bucket name"

    confirm_action "This will delete bucket $name and all contents"

    log_step "Deleting bucket: $name"
    aws s3 rb "s3://$name" --force
    log_success "Bucket deleted"
}

upload() {
    local bucket=$1
    local file=$2

    require_param "$bucket" "Bucket name"
    require_file "$file" "File"

    log_step "Uploading: $file"
    aws s3 cp "$file" "s3://$bucket/documents/$(basename "$file")"
    log_success "Uploaded to s3://$bucket/documents/$(basename "$file")"
}

upload_dir() {
    local bucket=$1
    local dir=$2

    require_param "$bucket" "Bucket name"
    require_directory "$dir" "Directory"

    log_step "Uploading directory: $dir"
    aws s3 sync "$dir" "s3://$bucket/documents/" --exclude ".*"
    log_success "Uploaded to s3://$bucket/documents/"
}

list() {
    local bucket=$1
    local prefix=${2:-"documents"}

    require_param "$bucket" "Bucket name"

    log_step "Listing: s3://$bucket/$prefix/"
    aws s3 ls "s3://$bucket/$prefix/" --human-readable --recursive
}

# =============================================================================
# Full Stack Orchestration
# =============================================================================
deploy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_info "Deploying Bedrock stack: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - S3 bucket for document storage"
    echo "  - IAM role for Bedrock access"
    echo "  - Sample documents"
    echo ""
    echo -e "${YELLOW}Note: Knowledge Base requires OpenSearch Serverless (manual setup)${NC}"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    local account_id=$(get_account_id)
    local region=$(get_region)

    # Create S3 bucket
    log_step "Step 1/3: Creating S3 bucket..."
    local bucket_name="${stack_name}-bedrock-docs-${account_id}"
    if [ "$region" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket already exists"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$region" \
            --create-bucket-configuration LocationConstraint="$region" 2>/dev/null || log_info "Bucket already exists"
    fi
    log_info "Bucket: $bucket_name"

    # Create sample documents
    log_step "Step 2/3: Creating sample documents..."

    cat << 'EOF' > /tmp/company-policy.txt
Company Policy Document

1. Work Hours
   - Standard work hours are 9:00 AM to 5:00 PM, Monday through Friday.
   - Flexible work arrangements may be available with manager approval.
   - Remote work is permitted up to 2 days per week.

2. Leave Policy
   - Annual leave: 20 days per year
   - Sick leave: 10 days per year
   - Parental leave: 12 weeks paid leave

3. Expense Policy
   - Business travel expenses are reimbursed within 30 days.
   - Maximum daily meal allowance: $50
   - Hotel bookings must be pre-approved for stays over $200/night.

4. IT Policy
   - All devices must have encryption enabled.
   - Password must be changed every 90 days.
   - Two-factor authentication is required for all systems.

5. Code of Conduct
   - Treat all colleagues with respect and professionalism.
   - Report any concerns to HR immediately.
   - Maintain confidentiality of company information.
EOF

    cat << 'EOF' > /tmp/product-guide.txt
Product User Guide

Getting Started
===============
Welcome to our product! This guide will help you get started quickly.

Installation
------------
1. Download the installer from our website
2. Run the installer and follow the prompts
3. Enter your license key when prompted
4. Restart your computer to complete installation

Basic Features
--------------
- Dashboard: View all your projects at a glance
- Reports: Generate detailed analytics reports
- Settings: Customize your experience
- Integrations: Connect with third-party services

Advanced Features
-----------------
- API Access: Programmatic access to all features
- Webhooks: Real-time notifications
- Custom workflows: Automate repetitive tasks

Troubleshooting
---------------
Q: Application won't start
A: Try reinstalling or contact support

Q: Login issues
A: Reset your password via the forgot password link

Q: Performance is slow
A: Clear cache and restart the application

Support
-------
- Email: support@example.com
- Phone: 1-800-EXAMPLE
- Hours: 24/7
EOF

    cat << 'EOF' > /tmp/faq.txt
Frequently Asked Questions

Q: What is your refund policy?
A: We offer a full refund within 30 days of purchase. After 30 days, refunds are prorated based on usage.

Q: How do I cancel my subscription?
A: You can cancel anytime from your account settings. Your access continues until the end of the billing period.

Q: Is my data secure?
A: Yes, we use AES-256 encryption for data at rest and TLS 1.3 for data in transit. We are SOC 2 Type II certified.

Q: Can I export my data?
A: Yes, you can export all your data in CSV or JSON format from the settings page.

Q: Do you offer enterprise pricing?
A: Yes, contact our sales team for custom enterprise plans with volume discounts.

Q: What integrations are available?
A: We integrate with Slack, Microsoft Teams, Salesforce, HubSpot, and 50+ other services.

Q: Is there a mobile app?
A: Yes, we have iOS and Android apps available in the respective app stores.

Q: How do I contact support?
A: Email support@example.com or use the live chat feature in the app.
EOF

    aws s3 cp /tmp/company-policy.txt "s3://$bucket_name/documents/"
    aws s3 cp /tmp/product-guide.txt "s3://$bucket_name/documents/"
    aws s3 cp /tmp/faq.txt "s3://$bucket_name/documents/"
    rm -f /tmp/company-policy.txt /tmp/product-guide.txt /tmp/faq.txt

    log_info "Uploaded 3 sample documents"

    # Create IAM role
    log_step "Step 3/3: Creating IAM role..."
    local role_name="${stack_name}-bedrock-role"

    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "bedrock.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
)
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || log_info "Role already exists"

    local bedrock_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:ListBucket"],
            "Resource": ["arn:aws:s3:::$bucket_name", "arn:aws:s3:::$bucket_name/*"]
        }
    ]
}
EOF
)
    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "${stack_name}-bedrock-policy" \
        --policy-document "$bedrock_policy"

    log_info "IAM Role: $role_name"

    echo ""
    log_success "Deployment complete!"
    echo ""
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo "Stack Name:  $stack_name"
    echo "S3 Bucket:   $bucket_name"
    echo "IAM Role:    $role_name"
    echo "Region:      $region"
    echo ""
    echo -e "${YELLOW}=== Quick Start ===${NC}"
    echo ""
    echo "1. Test text generation:"
    echo "   $0 chat 'Hello, what can you help me with?'"
    echo ""
    echo "2. Test with documents (no KB required):"
    echo "   # Read document and ask about it"
    echo "   aws s3 cp s3://$bucket_name/documents/faq.txt /tmp/faq.txt"
    echo "   $0 chat \"Based on this FAQ, what is the refund policy? \$(cat /tmp/faq.txt)\""
    echo ""
    echo "3. Create Knowledge Base (for RAG):"
    echo "   # Use AWS Console for guided setup:"
    echo "   https://$region.console.aws.amazon.com/bedrock/home?region=$region#/knowledge-bases"
    echo ""
    echo "4. Generate image:"
    echo "   $0 image 'A serene mountain landscape at sunset' landscape.png"
    echo ""
    echo -e "${YELLOW}=== Model Access ===${NC}"
    echo "Ensure you have enabled model access in Bedrock Console:"
    echo "  https://$region.console.aws.amazon.com/bedrock/home?region=$region#/modelaccess"
}

destroy() {
    local stack_name=$1
    require_param "$stack_name" "Stack name"

    log_warn "This will destroy all resources for: $stack_name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - S3 bucket and all documents"
    echo "  - IAM role and policies"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    local account_id=$(get_account_id)

    # Delete S3 bucket
    log_step "Deleting S3 bucket..."
    local bucket_name="${stack_name}-bedrock-docs-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || log_info "Bucket not found or already deleted"

    # Delete IAM role
    log_step "Deleting IAM role..."
    local role_name="${stack_name}-bedrock-role"
    aws iam delete-role-policy --role-name "$role_name" --policy-name "${stack_name}-bedrock-policy" 2>/dev/null || true
    aws iam delete-role --role-name "$role_name" 2>/dev/null || true

    log_success "Destroyed all resources for: $stack_name"
}

status() {
    local stack_name=${1:-}

    log_info "Checking Bedrock status${stack_name:+ for stack: $stack_name}..."
    echo ""

    echo -e "${BLUE}=== Foundation Models (Text) ===${NC}"
    aws bedrock list-foundation-models \
        --by-output-modality TEXT \
        --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ModelId:modelId,Provider:providerName}' \
        --output table 2>/dev/null | head -20 || echo "Unable to list models"

    echo -e "\n${BLUE}=== Knowledge Bases ===${NC}"
    aws bedrock-agent list-knowledge-bases \
        --query 'knowledgeBaseSummaries[].{Id:knowledgeBaseId,Name:name,Status:status}' \
        --output table 2>/dev/null || echo "No Knowledge Bases found"

    if [ -n "$stack_name" ]; then
        local account_id=$(get_account_id)
        local bucket_name="${stack_name}-bedrock-docs-${account_id}"

        echo -e "\n${BLUE}=== S3 Bucket ===${NC}"
        aws s3 ls "s3://$bucket_name/" 2>/dev/null || echo "Bucket not found: $bucket_name"

        echo -e "\n${BLUE}=== IAM Role ===${NC}"
        aws iam get-role --role-name "${stack_name}-bedrock-role" \
            --query 'Role.{RoleName:RoleName,Arn:Arn}' \
            --output table 2>/dev/null || echo "Role not found"
    fi
}

# =============================================================================
# Main Command Handler
# =============================================================================
check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    # Full stack
    deploy)
        deploy "$@"
        ;;
    destroy)
        destroy "$@"
        ;;
    status)
        status "$@"
        ;;

    # Model Management
    models)
        models
        ;;
    models-text)
        models_text
        ;;
    models-image)
        models_image
        ;;
    models-embedding)
        models_embedding
        ;;
    model-access)
        model_access
        ;;
    model-info)
        model_info "$@"
        ;;

    # Text Generation
    invoke)
        invoke_model "$@"
        ;;
    chat)
        chat "$@"
        ;;
    titan)
        titan "$@"
        ;;

    # Image Generation
    image)
        image "$@"
        ;;
    titan-image)
        titan_image "$@"
        ;;

    # Embeddings
    embed)
        embed "$@"
        ;;
    embed-file)
        embed_file "$@"
        ;;

    # Knowledge Base
    kb-create)
        kb_create "$@"
        ;;
    kb-list)
        kb_list
        ;;
    kb-show)
        kb_show "$@"
        ;;
    kb-delete)
        kb_delete "$@"
        ;;
    kb-sync)
        kb_sync "$@"
        ;;
    kb-query)
        kb_query "$@"
        ;;

    # Data Sources
    ds-create)
        ds_create "$@"
        ;;
    ds-list)
        ds_list "$@"
        ;;
    ds-delete)
        ds_delete "$@"
        ;;

    # S3
    bucket-create)
        bucket_create "$@"
        ;;
    bucket-delete)
        bucket_delete "$@"
        ;;
    upload)
        upload "$@"
        ;;
    upload-dir)
        upload_dir "$@"
        ;;
    list)
        list "$@"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
