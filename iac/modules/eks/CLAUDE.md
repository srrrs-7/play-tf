# CLAUDE.md - Amazon EKS

Amazon EKS クラスターを作成するTerraformモジュール。マネージドノードグループ、Fargateプロファイル、IRSA対応。

## Overview

このモジュールは以下のリソースを作成します:
- EKS Cluster
- EKS Node Group (マネージドノードグループ)
- EKS Fargate Profile
- EKS Add-ons (CoreDNS, kube-proxy, VPC CNI等)
- OIDC Provider (IRSA用)
- IAM Roles (Cluster, Node, Fargate)
- CloudWatch Log Group
- Security Groups (オプション)

## Key Resources

- `aws_eks_cluster.main` - EKSクラスター本体
- `aws_eks_node_group.main` - マネージドノードグループ (for_each)
- `aws_eks_fargate_profile.main` - Fargateプロファイル (for_each)
- `aws_eks_addon.main` - EKSアドオン (for_each)
- `aws_iam_openid_connect_provider.cluster` - OIDC Provider
- `aws_iam_role.cluster` - クラスターIAMロール
- `aws_iam_role.node` - ノードIAMロール
- `aws_iam_role.fargate` - Fargate IAMロール
- `aws_cloudwatch_log_group.cluster` - コントロールプレーンログ

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| cluster_name | string | EKSクラスター名 |
| cluster_version | string | Kubernetesバージョン (default: 1.28) |
| vpc_id | string | VPC ID |
| subnet_ids | list(string) | EKSクラスター用サブネットID |
| create_cluster_role | bool | クラスターIAMロールを作成するか (default: true) |
| endpoint_private_access | bool | プライベートエンドポイント (default: true) |
| endpoint_public_access | bool | パブリックエンドポイント (default: true) |
| public_access_cidrs | list(string) | パブリックアクセス許可CIDR |
| cluster_encryption_config | object | シークレット暗号化設定 |
| enabled_cluster_log_types | list(string) | 有効にするログタイプ |
| node_groups | map(object) | マネージドノードグループ設定 |
| create_node_role | bool | ノードIAMロールを作成するか (default: true) |
| node_additional_policies | list(string) | ノードロールに追加するポリシー |
| fargate_profiles | map(object) | Fargateプロファイル設定 |
| cluster_addons | map(object) | EKSアドオン設定 |
| enable_irsa | bool | IRSAを有効にするか (default: true) |
| create_cluster_security_group | bool | 追加のクラスターSGを作成するか |
| create_node_security_group | bool | 追加のノードSGを作成するか |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| cluster_id | EKSクラスターID |
| cluster_name | EKSクラスター名 |
| cluster_arn | EKSクラスターARN |
| cluster_endpoint | EKSクラスターエンドポイント |
| cluster_version | EKSクラスターバージョン |
| cluster_certificate_authority_data | クラスター証明書データ (sensitive) |
| cluster_oidc_issuer_url | OIDC Provider URL |
| oidc_provider_arn | OIDC Provider ARN |
| cluster_security_group_id | クラスターセキュリティグループID |
| cluster_role_arn | クラスターIAMロールARN |
| node_groups | ノードグループ情報マップ |
| node_role_arn | ノードIAMロールARN |
| fargate_profiles | Fargateプロファイル情報マップ |
| cluster_addons | EKSアドオン情報マップ |
| kubeconfig_command | kubeconfig更新コマンド |

## Usage Example

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name    = "${var.project_name}-${var.environment}-eks"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = ["0.0.0.0/0"]

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  node_groups = {
    main = {
      name           = "main"
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      disk_size      = 50
    }
    spot = {
      name           = "spot"
      instance_types = ["t3.medium", "t3.large"]
      capacity_type  = "SPOT"
      desired_size   = 2
      min_size       = 0
      max_size       = 10
    }
  }

  cluster_addons = {
    coredns = {
      resolve_conflicts_on_create = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts_on_create = "OVERWRITE"
    }
  }

  enable_irsa = true

  tags = var.tags
}
```

## Important Notes

- IRSA (IAM Roles for Service Accounts) でPod単位のIAM権限管理
- マネージドノードグループはEC2オートスケーリンググループを自動作成
- SPOTインスタンスで `capacity_type = "SPOT"` を設定
- Fargateはサーバーレスで特定のNamespace/Labelに対応
- コントロールプレーンログはCloudWatch Logsに出力
- アドオンはマネージド更新で最新に保持
- `kubeconfig_command` 出力で簡単にkubeconfig設定可能
- シークレット暗号化は `cluster_encryption_config` でKMSキーを指定
