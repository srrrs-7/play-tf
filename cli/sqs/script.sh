#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# SQS Operations Script
# Provides common SQS operations using AWS CLI

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list-queues [prefix]                - List all SQS queues"
    echo "  create-queue <queue-name>           - Create a new SQS queue"
    echo "  create-fifo-queue <queue-name>      - Create a new FIFO queue"
    echo "  delete-queue <queue-url>            - Delete an SQS queue"
    echo "  get-queue-url <queue-name>          - Get queue URL by name"
    echo "  get-queue-attributes <queue-url>    - Get queue attributes"
    echo "  set-queue-attributes <queue-url>    - Set queue attributes"
    echo "  send-message <queue-url> <message>  - Send a message to queue"
    echo "  send-message-batch <queue-url> <file> - Send messages from JSON file"
    echo "  receive-messages <queue-url> [max]  - Receive messages from queue"
    echo "  delete-message <queue-url> <receipt-handle> - Delete a message"
    echo "  purge-queue <queue-url>             - Delete all messages in queue"
    echo "  get-queue-stats <queue-url>         - Get queue statistics"
    echo "  set-visibility-timeout <queue-url> <seconds> - Set visibility timeout"
    echo "  set-message-retention <queue-url> <seconds> - Set message retention period"
    echo "  set-dead-letter-queue <queue-url> <dlq-arn> <max-receives> - Configure DLQ"
    echo "  enable-long-polling <queue-url> <seconds> - Enable long polling"
    echo ""
    exit 1
}

# List all SQS queues
list_queues() {
    local prefix=$1
    echo -e "${GREEN}Listing SQS queues...${NC}"

    if [ -n "$prefix" ]; then
        aws sqs list-queues --queue-name-prefix "$prefix"
    else
        aws sqs list-queues
    fi
}

# Create a standard SQS queue
create_queue() {
    local queue_name=$1
    if [ -z "$queue_name" ]; then
        echo -e "${RED}Error: Queue name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating queue: $queue_name${NC}"
    aws sqs create-queue --queue-name "$queue_name"
    echo -e "${GREEN}Queue created successfully${NC}"
}

# Create a FIFO queue
create_fifo_queue() {
    local queue_name=$1
    if [ -z "$queue_name" ]; then
        echo -e "${RED}Error: Queue name is required${NC}"
        exit 1
    fi

    if [[ ! "$queue_name" =~ \.fifo$ ]]; then
        queue_name="${queue_name}.fifo"
    fi

    echo -e "${GREEN}Creating FIFO queue: $queue_name${NC}"
    aws sqs create-queue \
        --queue-name "$queue_name" \
        --attributes FifoQueue=true,ContentBasedDeduplication=true
    echo -e "${GREEN}FIFO queue created successfully${NC}"
}

# Delete an SQS queue
delete_queue() {
    local queue_url=$1
    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete queue: $queue_url${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting queue: $queue_url${NC}"
    aws sqs delete-queue --queue-url "$queue_url"
    echo -e "${GREEN}Queue deleted successfully${NC}"
}

# Get queue URL by name
get_queue_url() {
    local queue_name=$1
    if [ -z "$queue_name" ]; then
        echo -e "${RED}Error: Queue name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting URL for queue: $queue_name${NC}"
    aws sqs get-queue-url --queue-name "$queue_name"
}

# Get queue attributes
get_queue_attributes() {
    local queue_url=$1
    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting attributes for queue: $queue_url${NC}"
    aws sqs get-queue-attributes \
        --queue-url "$queue_url" \
        --attribute-names All
}

# Set queue attributes
set_queue_attributes() {
    local queue_url=$1
    shift

    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        echo "Usage: $0 set-queue-attributes <queue-url> <attribute-name> <value>"
        exit 1
    fi

    echo -e "${GREEN}Setting attributes for queue: $queue_url${NC}"
    aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        "$@"
    echo -e "${GREEN}Attributes updated successfully${NC}"
}

# Send a message to queue
send_message() {
    local queue_url=$1
    local message=$2

    if [ -z "$queue_url" ] || [ -z "$message" ]; then
        echo -e "${RED}Error: Queue URL and message are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Sending message to queue: $queue_url${NC}"
    aws sqs send-message \
        --queue-url "$queue_url" \
        --message-body "$message"
    echo -e "${GREEN}Message sent successfully${NC}"
}

# Send messages in batch from JSON file
send_message_batch() {
    local queue_url=$1
    local file=$2

    if [ -z "$queue_url" ] || [ -z "$file" ]; then
        echo -e "${RED}Error: Queue URL and file path are required${NC}"
        exit 1
    fi

    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File does not exist: $file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Sending batch messages to queue: $queue_url${NC}"
    aws sqs send-message-batch \
        --queue-url "$queue_url" \
        --entries "file://$file"
    echo -e "${GREEN}Batch messages sent successfully${NC}"
}

# Receive messages from queue
receive_messages() {
    local queue_url=$1
    local max_messages=${2:-1}

    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Receiving up to $max_messages message(s) from queue: $queue_url${NC}"
    aws sqs receive-message \
        --queue-url "$queue_url" \
        --max-number-of-messages "$max_messages" \
        --attribute-names All \
        --message-attribute-names All
}

# Delete a message from queue
delete_message() {
    local queue_url=$1
    local receipt_handle=$2

    if [ -z "$queue_url" ] || [ -z "$receipt_handle" ]; then
        echo -e "${RED}Error: Queue URL and receipt handle are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Deleting message from queue: $queue_url${NC}"
    aws sqs delete-message \
        --queue-url "$queue_url" \
        --receipt-handle "$receipt_handle"
    echo -e "${GREEN}Message deleted successfully${NC}"
}

# Purge all messages from queue
purge_queue() {
    local queue_url=$1
    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete all messages in queue: $queue_url${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Purging queue: $queue_url${NC}"
    aws sqs purge-queue --queue-url "$queue_url"
    echo -e "${GREEN}Queue purged successfully${NC}"
}

# Get queue statistics
get_queue_stats() {
    local queue_url=$1
    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting statistics for queue: $queue_url${NC}"
    local attributes=$(aws sqs get-queue-attributes \
        --queue-url "$queue_url" \
        --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed \
        --output json)

    echo "$attributes" | jq -r '.Attributes |
        "Messages Available: " + .ApproximateNumberOfMessages + "\n" +
        "Messages In Flight: " + .ApproximateNumberOfMessagesNotVisible + "\n" +
        "Messages Delayed: " + .ApproximateNumberOfMessagesDelayed'
}

# Set visibility timeout
set_visibility_timeout() {
    local queue_url=$1
    local timeout=$2

    if [ -z "$queue_url" ] || [ -z "$timeout" ]; then
        echo -e "${RED}Error: Queue URL and timeout are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting visibility timeout to $timeout seconds for queue: $queue_url${NC}"
    aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        --attributes VisibilityTimeout="$timeout"
    echo -e "${GREEN}Visibility timeout updated successfully${NC}"
}

# Set message retention period
set_message_retention() {
    local queue_url=$1
    local retention=$2

    if [ -z "$queue_url" ] || [ -z "$retention" ]; then
        echo -e "${RED}Error: Queue URL and retention period are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting message retention to $retention seconds for queue: $queue_url${NC}"
    aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        --attributes MessageRetentionPeriod="$retention"
    echo -e "${GREEN}Message retention updated successfully${NC}"
}

# Configure dead letter queue
set_dead_letter_queue() {
    local queue_url=$1
    local dlq_arn=$2
    local max_receives=$3

    if [ -z "$queue_url" ] || [ -z "$dlq_arn" ] || [ -z "$max_receives" ]; then
        echo -e "${RED}Error: Queue URL, DLQ ARN, and max receives are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Configuring dead letter queue for: $queue_url${NC}"
    local redrive_policy="{\"deadLetterTargetArn\":\"$dlq_arn\",\"maxReceiveCount\":\"$max_receives\"}"

    aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        --attributes RedrivePolicy="$redrive_policy"
    echo -e "${GREEN}Dead letter queue configured successfully${NC}"
}

# Enable long polling
enable_long_polling() {
    local queue_url=$1
    local wait_time=${2:-20}

    if [ -z "$queue_url" ]; then
        echo -e "${RED}Error: Queue URL is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Enabling long polling ($wait_time seconds) for queue: $queue_url${NC}"
    aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        --attributes ReceiveMessageWaitTimeSeconds="$wait_time"
    echo -e "${GREEN}Long polling enabled successfully${NC}"
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    list-queues)
        list_queues "$@"
        ;;
    create-queue)
        create_queue "$@"
        ;;
    create-fifo-queue)
        create_fifo_queue "$@"
        ;;
    delete-queue)
        delete_queue "$@"
        ;;
    get-queue-url)
        get_queue_url "$@"
        ;;
    get-queue-attributes)
        get_queue_attributes "$@"
        ;;
    set-queue-attributes)
        set_queue_attributes "$@"
        ;;
    send-message)
        send_message "$@"
        ;;
    send-message-batch)
        send_message_batch "$@"
        ;;
    receive-messages)
        receive_messages "$@"
        ;;
    delete-message)
        delete_message "$@"
        ;;
    purge-queue)
        purge_queue "$@"
        ;;
    get-queue-stats)
        get_queue_stats "$@"
        ;;
    set-visibility-timeout)
        set_visibility_timeout "$@"
        ;;
    set-message-retention)
        set_message_retention "$@"
        ;;
    set-dead-letter-queue)
        set_dead_letter_queue "$@"
        ;;
    enable-long-polling)
        enable_long_polling "$@"
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac
