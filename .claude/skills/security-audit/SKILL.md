---
name: security-audit
description: Audit Terraform code and AWS resources for security best practices
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
---

# Security Audit Skill

Audits Terraform code and AWS configurations for security issues.

## Usage

```
/security-audit [path]
```

- `path`: Directory to audit (default: entire `iac/` directory)

## Audit Categories

### 1. S3 Bucket Security

**Check for:**
- [ ] Public access blocked
- [ ] Server-side encryption enabled
- [ ] Versioning enabled (for important data)
- [ ] Logging enabled
- [ ] Lifecycle policies configured

**Terraform patterns to find:**
```hcl
# GOOD
block_public_acls       = true
block_public_policy     = true
sse_algorithm          = "AES256"

# BAD
block_public_acls       = false
acl                     = "public-read"
```

**Search commands:**
```bash
grep -r "block_public_acls\s*=\s*false" iac/
grep -r "acl\s*=\s*\"public" iac/
grep -r "aws_s3_bucket\." iac/ | grep -v "encryption\|public_access_block"
```

### 2. IAM Security

**Check for:**
- [ ] No wildcard (*) actions on sensitive resources
- [ ] No hardcoded credentials
- [ ] Least privilege principle
- [ ] No inline policies (prefer managed)

**Patterns to detect:**
```bash
# Overly permissive
grep -r '"Action"\s*:\s*"\*"' iac/
grep -r '"Resource"\s*:\s*"\*"' iac/
grep -r "AdministratorAccess" iac/

# Hardcoded secrets
grep -ri "password\s*=" iac/
grep -ri "secret.*=.*\"" iac/
grep -ri "api.key" iac/
```

### 3. Network Security

**Check for:**
- [ ] No 0.0.0.0/0 ingress on sensitive ports
- [ ] Private subnets for databases
- [ ] VPC endpoints for AWS services
- [ ] Security group rules documented

**Patterns:**
```bash
# Open to world
grep -r "0.0.0.0/0" iac/
grep -r "cidr_blocks.*0.0.0.0" iac/

# Sensitive ports open
grep -rE "(22|3306|5432|27017|6379)" iac/ | grep -i "ingress\|from_port"
```

### 4. Encryption

**Check for:**
- [ ] RDS encryption enabled
- [ ] DynamoDB encryption enabled
- [ ] EBS encryption enabled
- [ ] KMS keys for sensitive data

**Patterns:**
```bash
# Missing encryption
grep -r "storage_encrypted\s*=\s*false" iac/
grep -r "server_side_encryption\s*{" iac/ -A2 | grep "enabled\s*=\s*false"
```

### 5. Logging & Monitoring

**Check for:**
- [ ] CloudWatch log groups with retention
- [ ] CloudTrail enabled
- [ ] VPC Flow Logs enabled
- [ ] Access logging on ALB/S3

**Patterns:**
```bash
# Missing retention
grep -r "aws_cloudwatch_log_group" iac/ -A5 | grep -v "retention_in_days"
```

### 6. Secrets in Code

**Check for:**
- [ ] No AWS keys in code
- [ ] No passwords in code
- [ ] No API tokens in code
- [ ] Using Secrets Manager/Parameter Store

**Patterns:**
```bash
# AWS credentials
grep -rE "AKIA[0-9A-Z]{16}" .
grep -rE "aws_access_key_id\s*=" .
grep -rE "aws_secret_access_key\s*=" .

# Common secrets
grep -ri "password\s*=\s*\"[^\"]+\"" . --include="*.tf"
grep -ri "api_key\s*=\s*\"" . --include="*.tf"
```

## Audit Report Format

```markdown
# Security Audit Report

Date: {date}
Scope: {path}

## Summary
- Critical: X issues
- High: X issues
- Medium: X issues
- Low: X issues

## Critical Issues
{List critical security issues}

## High Priority
{List high priority issues}

## Recommendations
{Specific remediation steps}

## Compliant Items
{What's done well}
```

## Automated Checks

Run these commands for quick audit:

```bash
# S3 public access
grep -r "block_public.*false" iac/

# Wildcard permissions
grep -r '"*"' iac/ --include="*.tf"

# Hardcoded values that might be secrets
grep -rE "(password|secret|key|token)\s*=\s*\"[^$]" iac/

# Missing encryption
grep -r "encrypted\s*=\s*false" iac/
```

## Integration with CI/CD

Consider adding:
- tfsec
- checkov
- terrascan
- AWS Config rules
