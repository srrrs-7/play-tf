---
name: aws-auth
description: Check AWS authentication status and help configure credentials
disable-model-invocation: true
allowed-tools: Bash, Read
---

Check AWS authentication status and provide guidance.

Current AWS identity:
!`aws sts get-caller-identity 2>/dev/null || echo "ERROR: Not authenticated or AWS CLI not configured"`

Current region:
!`echo "Region: ${AWS_DEFAULT_REGION:-ap-northeast-1 (default)}"`

If not authenticated, provide guidance on authentication methods:

## Method 1: Access Keys
```bash
aws configure
# Or set environment variables:
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-northeast-1"
```

## Method 2: AWS SSO
```bash
aws configure sso
aws sso login --profile your-profile
```

## Method 3: IAM Identity Center
```bash
aws login
```

## Verify Authentication
```bash
aws sts get-caller-identity
```

If authenticated, show:
- Account ID
- User/Role ARN
- Available permissions (basic check)
