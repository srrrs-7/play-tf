# CloudFront → ALB → EKS → Aurora CLI

CloudFront、ALB、Amazon EKS、Auroraを使用したKubernetesアーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [ALB] → [EKS Cluster] → [Aurora]
                                          ↓
                                    [Kubernetes Pods]
                                          ↓
                                        [ECR]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-k8s-app` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-k8s-app` |
| `status <stack-name>` | 全コンポーネントの状態表示 | `./script.sh status my-k8s-app` |

### EKS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `eks-create <name> <role-arn> <subnet-ids>` | EKSクラスター作成 | `./script.sh eks-create my-cluster arn:aws:iam:... subnet-a,subnet-b` |
| `eks-delete <name>` | EKSクラスター削除 | `./script.sh eks-delete my-cluster` |
| `eks-list` | EKSクラスター一覧 | `./script.sh eks-list` |
| `eks-update-kubeconfig <name>` | kubeconfigを更新 | `./script.sh eks-update-kubeconfig my-cluster` |
| `nodegroup-create <cluster> <name> <role-arn> <subnets> <types>` | ノードグループ作成 | `./script.sh nodegroup-create my-cluster my-nodes arn:... subnet-a,subnet-b t3.medium` |
| `nodegroup-delete <cluster> <name>` | ノードグループ削除 | `./script.sh nodegroup-delete my-cluster my-nodes` |
| `nodegroup-scale <cluster> <name> <min> <max> <desired>` | ノードスケーリング | `./script.sh nodegroup-scale my-cluster my-nodes 2 10 4` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <alb-dns> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create my-alb.elb.amazonaws.com my-app` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234...` |
| `cf-invalidate <dist-id> <path>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/*"` |

### ALB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `alb-create <name> <vpc-id> <subnet-ids>` | ALB作成 | `./script.sh alb-create my-alb vpc-123... subnet-a,subnet-b` |
| `alb-delete <alb-arn>` | ALB削除 | `./script.sh alb-delete arn:aws:...` |

### Aurora操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `aurora-create <cluster-id> <user> <pass> <subnet-group> <sg>` | Auroraクラスター作成 | `./script.sh aurora-create my-db admin pass123 my-subnet sg-...` |
| `aurora-delete <cluster-id>` | Auroraクラスター削除 | `./script.sh aurora-delete my-db` |
| `aurora-status <cluster-id>` | ステータス確認 | `./script.sh aurora-status my-db` |

### ECR操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `ecr-create <name>` | リポジトリ作成 | `./script.sh ecr-create my-app` |
| `ecr-login` | ECRログイン | `./script.sh ecr-login` |
| `ecr-push <repo> <image> <tag>` | イメージプッシュ | `./script.sh ecr-push my-app my-app:latest v1.0` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-k8s-app

# kubeconfigを設定
./script.sh eks-update-kubeconfig my-k8s-app-cluster

# Kubernetesリソースをデプロイ
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# ノードスケーリング
./script.sh nodegroup-scale my-k8s-app-cluster my-nodes 3 10 5

# Aurora接続確認
./script.sh aurora-status my-k8s-app-db

# 全リソース削除
./script.sh destroy my-k8s-app
```

## 注意事項

- EKSクラスター作成には15-20分程度かかります
- AWS Load Balancer Controllerを別途インストールすることでIngress経由のALB統合が可能です
