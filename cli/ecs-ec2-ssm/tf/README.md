# ECS on EC2 with Session Manager - Terraform

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          VPC                                 │
│  ┌─────────────────┐          ┌─────────────────────────┐  │
│  │  Public Subnet  │          │     Private Subnet      │  │
│  │                 │          │                         │  │
│  │  ┌───────────┐  │          │  ┌─────────────────┐   │  │
│  │  │NAT Gateway│◄─┼──────────┼──┤ EC2 (ECS Agent) │   │  │
│  │  └─────┬─────┘  │          │  │ + SSM Agent     │   │  │
│  │        │        │          │  │ + Container     │   │  │
│  │        ▼        │          │  └─────────────────┘   │  │
│  │  ┌───────────┐  │          │                         │  │
│  │  │   IGW     │  │          └─────────────────────────┘  │
│  │  └─────┬─────┘  │                      ▲                 │
│  └────────┼────────┘                      │                 │
│           │                               │                 │
└───────────┼───────────────────────────────┼─────────────────┘
            │                               │
            ▼                               │
      ┌──────────┐                   ┌──────────────┐
      │ Internet │                   │Session Manager│
      └──────────┘                   │   Console    │
                                     └──────────────┘
```

## Features

- **Private Subnet**: EC2 instances are deployed in private subnets without public IPs
- **NAT Gateway**: Provides outbound internet access for EC2 instances (ECR pull, etc.)
- **ECS Exec**: Direct container access via AWS CLI (no SSH/bastion needed)
- **Session Manager**: SSH-less access to EC2 instances (no bastion host needed)
- **ECS on EC2**: Container workloads running on EC2 instances (not Fargate)
- **Auto Scaling**: Auto Scaling Group for EC2 instances with ECS Capacity Provider

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0.0
- Session Manager plugin for AWS CLI (for `ssm start-session`)

```bash
# Install Session Manager plugin (macOS)
brew install --cask session-manager-plugin

# Install Session Manager plugin (Linux)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

## Quick Start

```bash
# 1. Copy example variables
cp terraform.tfvars.example terraform.tfvars

# 2. Edit variables
vi terraform.tfvars

# 3. Initialize Terraform
terraform init

# 4. Preview changes
terraform plan

# 5. Apply configuration
terraform apply
```

## Container Access Methods

### Comparison

| Method | Command | Use Case |
|--------|---------|----------|
| **ECS Exec** (Recommended) | `aws ecs execute-command` | Direct container access |
| Session Manager | `aws ssm start-session` | EC2 instance access |
| EC2 + docker | Session Manager → `docker exec` | Access all containers on EC2 |

## ECS Exec - Direct Container Access (Recommended)

ECS Exec allows you to directly access containers without SSH. This is the recommended method.

### Prerequisites

- Session Manager plugin installed
- `enable_execute_command = true` in ECS service (enabled by default)

### Usage

```bash
# 1. List running tasks
aws ecs list-tasks --cluster <stack-name> --service-name <stack-name>-svc

# 2. Get task ID
TASK_ID=$(aws ecs list-tasks --cluster <stack-name> \
  --query 'taskArns[0]' --output text | rev | cut -d'/' -f1 | rev)

# 3. Connect to container (interactive shell)
aws ecs execute-command \
  --cluster <stack-name> \
  --task $TASK_ID \
  --container <stack-name> \
  --interactive \
  --command "/bin/sh"

# Run a single command
aws ecs execute-command \
  --cluster <stack-name> \
  --task $TASK_ID \
  --container <stack-name> \
  --command "cat /etc/os-release"
```

### Troubleshooting ECS Exec

```bash
# Check if ECS Exec is enabled on the task
aws ecs describe-tasks --cluster <stack-name> --tasks $TASK_ID \
  --query 'tasks[0].enableExecuteCommand'

# Check managed agent status
aws ecs describe-tasks --cluster <stack-name> --tasks $TASK_ID \
  --query 'tasks[0].containers[0].managedAgents'
```

## Connect to EC2 via Session Manager

```bash
# 1. List running instances
aws ec2 describe-instances \
  --filters "Name=tag:ECSCluster,Values=<stack-name>" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]' \
  --output table

# 2. Connect to instance
aws ssm start-session --target <instance-id>

# 3. Check containers (on EC2)
docker ps
docker logs <container-id>
docker exec -it <container-id> /bin/sh
```

## Container Operations on EC2

After connecting via Session Manager:

```bash
# List running containers
docker ps

# View container logs
docker logs <container-id>
docker logs -f <container-id>  # Follow logs

# Enter container shell
docker exec -it <container-id> /bin/sh
docker exec -it <container-id> /bin/bash

# Check ECS agent status
curl -s http://localhost:51678/v1/metadata | jq .

# View ECS agent logs
cat /var/log/ecs/ecs-agent.log
```

## View Logs in CloudWatch

```bash
# Tail logs
aws logs tail /ecs/<stack-name> --follow

# Get recent logs
aws logs get-log-events \
  --log-group-name /ecs/<stack-name> \
  --log-stream-name <stream-name>
```

## Update Deployment

```bash
# Scale EC2 instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name <asg-name> \
  --desired-capacity 2

# Scale ECS tasks
aws ecs update-service \
  --cluster <stack-name> \
  --service <stack-name>-svc \
  --desired-count 2

# Update container image (modify terraform.tfvars)
container_image = "my-repo/my-image:v2"
terraform apply
```

## Destroy Resources

```bash
terraform destroy
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `stack_name` | Stack name (required) | - |
| `aws_region` | AWS region | `ap-northeast-1` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `asg_desired_capacity` | Desired number of EC2 instances | `1` |
| `container_image` | Container image URI | `nginx:latest` |
| `container_port` | Container port | `80` |
| `create_ecs_service` | Whether to create ECS service | `true` |
| `enable_execute_command` | Enable ECS Exec for container access | `true` |

See `variables.tf` for all available variables.

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `ecs_cluster_name` | ECS cluster name |
| `autoscaling_group_name` | Auto Scaling Group name |
| `cloudwatch_log_group_name` | CloudWatch log group name |
| `ecs_exec_command` | ECS Exec command examples |
| `ssm_connect_command` | Session Manager connection commands |
| `deployment_summary` | Full deployment summary with commands |

## Cost Considerations

- **NAT Gateway**: ~$0.045/hour + data transfer
- **EC2 Instance**: Varies by instance type (t3.micro ~$0.0104/hour)
- **CloudWatch Logs**: Storage and ingestion costs

To minimize costs for development:
- Use smaller instance types (`t3.micro`, `t3.small`)
- Set `asg_min_size = 0` when not in use
- Reduce log retention days

## Security Notes

- EC2 instances have no public IP addresses
- Session Manager provides audit logging
- Security group allows only VPC internal traffic and outbound
- IAM roles follow least privilege principle
- EBS volumes are encrypted by default
- IMDSv2 is enforced for enhanced security
