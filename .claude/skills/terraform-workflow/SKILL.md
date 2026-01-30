---
name: terraform-workflow
description: Complete Terraform workflow with guided init, plan, and apply steps
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
---

# Terraform Workflow Skill

Guides you through the complete Terraform workflow for this project.

## Usage

```
/terraform-workflow [environment] [action]
```

- `environment`: dev, stg, prd, s3, api (optional - will prompt if not provided)
- `action`: init, plan, apply, destroy (optional - will guide through workflow)

## Workflow Steps

### Step 1: Environment Selection

If no environment specified, list available environments:
```bash
ls -d iac/environments/*/
```

Available environments in this project:
- `dev` - Development environment
- `stg` - Staging environment
- `prd` - Production environment
- `s3` - S3 + Lambda presigned URL setup
- `api` - API Gateway + Lambda + DynamoDB setup

### Step 2: Pre-flight Checks

Before any Terraform operation:

1. **Check AWS Authentication**
   ```bash
   aws sts get-caller-identity
   ```

2. **Check terraform.tfvars**
   - If missing but `.example` exists, warn user to create it
   - Never commit tfvars files (they're gitignored)

3. **Check Lambda builds** (for s3 and api environments)
   - Verify `dist/` directory exists
   - If not, prompt to run build first

### Step 3: Initialize

```bash
cd iac/environments/{env}
terraform init
```

### Step 4: Validate & Format

```bash
terraform fmt -check
terraform validate
```

Fix any issues before proceeding.

### Step 5: Plan

```bash
terraform plan -out=tfplan
```

Review planned changes:
- Resources to add (green +)
- Resources to change (yellow ~)
- Resources to destroy (red -)

### Step 6: Apply (with confirmation)

```bash
terraform apply tfplan
```

**Safety Rules:**
- Always require explicit confirmation
- Never use `-auto-approve` for prd
- Show outputs after successful apply

### Step 7: Post-Apply

- Display all Terraform outputs
- Show relevant URLs, ARNs, endpoints
- Suggest next steps (testing, monitoring)

## Environment-Specific Notes

### s3 Environment
Before apply, build Lambda:
```bash
cd iac/environments/s3/s3-presigned-url
./build.sh
```

### api Environment
Before apply, build Lambda:
```bash
cd iac/environments/api/api-handler
./build.sh
```

## Rollback

If issues occur after apply:
```bash
terraform plan -destroy
terraform destroy  # Only if necessary
```

Or restore from state backup.
