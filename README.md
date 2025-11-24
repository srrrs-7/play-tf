# play-tf

# login

## AWS credentials
aws configure
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-northeast-1"

## AWS login
aws login

## AWS SSO
aws configure sso

# terraform

## 環境設定
cd iac/environments/*

## 初期化
terraform init

## フォーマット確認
terraform fmt -check

## 検証
terraform validate

## プラン確認
terraform plan

## 適用
terraform apply