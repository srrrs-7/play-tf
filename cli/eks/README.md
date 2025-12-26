# Amazon EKS CLI

Amazon EKS（Elastic Kubernetes Service）クラスターを構築・管理するためのCLIスクリプトです。

## アーキテクチャ

```
                     ┌─────────────────────────────────────────┐
                     │              AWS Cloud                   │
                     │                                         │
    ┌────────────────┼─────────────────────────────────────────┼────────────────┐
    │                │            VPC (10.0.0.0/16)            │                │
    │                │                                         │                │
    │  ┌─────────────┼─────────────┐  ┌───────────────────────┼─────────────┐  │
    │  │   Public Subnet (AZ-a)    │  │   Public Subnet (AZ-b)              │  │
    │  │   10.0.1.0/24             │  │   10.0.2.0/24                       │  │
    │  │   ┌─────────────────┐     │  │                                     │  │
    │  │   │   NAT Gateway   │     │  │                                     │  │
    │  │   └─────────────────┘     │  │                                     │  │
    │  └───────────────────────────┘  └─────────────────────────────────────┘  │
    │                                                                          │
    │  ┌───────────────────────────┐  ┌─────────────────────────────────────┐  │
    │  │  Private Subnet (AZ-a)    │  │   Private Subnet (AZ-b)             │  │
    │  │  10.0.11.0/24             │  │   10.0.12.0/24                      │  │
    │  │  ┌─────────────────────┐  │  │  ┌─────────────────────┐            │  │
    │  │  │   EKS Node (EC2)    │  │  │  │   EKS Node (EC2)    │            │  │
    │  │  └─────────────────────┘  │  │  └─────────────────────┘            │  │
    │  └───────────────────────────┘  └─────────────────────────────────────┘  │
    │                                                                          │
    │                    ┌─────────────────────────┐                           │
    │                    │   EKS Control Plane     │                           │
    │                    │   (AWS Managed)         │                           │
    │                    └─────────────────────────┘                           │
    └──────────────────────────────────────────────────────────────────────────┘
```

## 前提条件

1. **AWS CLI** がインストール・設定済み
2. **kubectl** がインストール済み
3. IAMユーザー/ロールに必要な権限がある

## クイックスタート

### 1. フルスタックデプロイ

```bash
./script.sh deploy my-cluster
```

これにより以下が作成されます（約20-30分）：
- VPC（パブリック/プライベートサブネット x 2 AZ）
- NAT Gateway
- EKSクラスター（コントロールプレーン）
- マネージドノードグループ（2x t3.medium）
- IAMロール（クラスター用、ノード用）
- コアAdd-ons（vpc-cni, coredns, kube-proxy）

### 2. クラスター接続確認

```bash
# kubeconfigを更新（deployで自動実行）
./script.sh kubeconfig my-cluster

# ノードを確認
kubectl get nodes

# クラスター情報
kubectl cluster-info
```

### 3. サンプルアプリケーションをデプロイ

```bash
./script.sh sample-deploy my-cluster

# アプリケーションを確認
kubectl get pods -n sample-app
kubectl get svc -n sample-app
```

## コマンド一覧

### フルスタック操作

| コマンド | 説明 |
|---------|------|
| `deploy <name> [version]` | VPC + EKS + ノードグループを一括作成 |
| `destroy <name>` | 全リソースを削除 |
| `status [name]` | ステータスを表示 |

### VPC操作

| コマンド | 説明 |
|---------|------|
| `vpc-create <name> [cidr]` | EKS用VPCを作成 |
| `vpc-list` | VPC一覧 |
| `vpc-delete <vpc-id>` | VPCを削除 |

### EKSクラスター操作

| コマンド | 説明 |
|---------|------|
| `cluster-create <name> <subnets> [version]` | クラスターを作成 |
| `cluster-list` | クラスター一覧 |
| `cluster-show <name>` | クラスター詳細 |
| `cluster-delete <name>` | クラスターを削除 |
| `cluster-update-version <name> <version>` | バージョンアップグレード |

### ノードグループ操作

| コマンド | 説明 |
|---------|------|
| `nodegroup-create <cluster> <name> <subnets> [type] [count]` | ノードグループを作成 |
| `nodegroup-list <cluster>` | ノードグループ一覧 |
| `nodegroup-show <cluster> <name>` | ノードグループ詳細 |
| `nodegroup-scale <cluster> <name> <count>` | スケール |
| `nodegroup-delete <cluster> <name>` | ノードグループを削除 |

### Fargateプロファイル

| コマンド | 説明 |
|---------|------|
| `fargate-create <cluster> <name> <subnets> <namespace>` | Fargateプロファイルを作成 |
| `fargate-list <cluster>` | Fargateプロファイル一覧 |
| `fargate-delete <cluster> <name>` | Fargateプロファイルを削除 |

### Add-ons

| コマンド | 説明 |
|---------|------|
| `addon-list <cluster>` | インストール済みAdd-on一覧 |
| `addon-install <cluster> <addon-name>` | Add-onをインストール |
| `addon-delete <cluster> <addon-name>` | Add-onを削除 |
| `addon-available` | 利用可能なAdd-on一覧 |

### kubectl設定

| コマンド | 説明 |
|---------|------|
| `kubeconfig <cluster>` | kubeconfigを更新 |
| `kubectl-test <cluster>` | 接続テスト |

### サンプルアプリケーション

| コマンド | 説明 |
|---------|------|
| `sample-deploy <cluster>` | nginxサンプルをデプロイ |
| `sample-delete <cluster>` | サンプルを削除 |

## Kubernetesバージョン

サポートされるバージョン（2024年時点）：
- 1.29（最新、デフォルト）
- 1.28
- 1.27
- 1.26

```bash
# 特定のバージョンでデプロイ
./script.sh deploy my-cluster 1.28

# バージョンアップグレード
./script.sh cluster-update-version my-cluster 1.29
```

## インスタンスタイプ

### マネージドノードグループ

| タイプ | vCPU | メモリ | 用途 |
|--------|------|--------|------|
| t3.medium | 2 | 4GB | 開発・テスト（デフォルト） |
| t3.large | 2 | 8GB | 小規模本番 |
| m5.large | 2 | 8GB | 本番ワークロード |
| m5.xlarge | 4 | 16GB | 中規模本番 |
| c5.xlarge | 4 | 8GB | CPU集約型 |
| r5.large | 2 | 16GB | メモリ集約型 |

```bash
# カスタムインスタンスタイプでノードグループ作成
./script.sh nodegroup-create my-cluster workers subnet-xxx,subnet-yyy m5.large 3
```

### Fargate

Fargateはサーバーレスで、ポッドごとに自動でリソースが割り当てられます。

```bash
# Fargateプロファイルを作成
./script.sh fargate-create my-cluster fargate-profile subnet-xxx,subnet-yyy default
```

## Add-ons

### コアAdd-ons（自動インストール）

| Add-on | 説明 |
|--------|------|
| vpc-cni | VPCネットワーキング |
| coredns | DNS解決 |
| kube-proxy | ネットワークプロキシ |

### オプションAdd-ons

```bash
# EBS CSIドライバー（永続ボリューム用）
./script.sh addon-install my-cluster aws-ebs-csi-driver

# EFS CSIドライバー（共有ファイルシステム用）
./script.sh addon-install my-cluster aws-efs-csi-driver

# AWS Load Balancer Controller
# ※ Helmでのインストールを推奨
```

## 料金

### EKS料金

| コンポーネント | 料金 |
|---------------|------|
| EKSクラスター | $0.10/時間（約$73/月） |
| マネージドノード | EC2インスタンス料金 |
| Fargate | vCPU/時間 + メモリ/時間 |

### 参考コスト（最小構成）

```
EKSクラスター:     $0.10/時間
t3.medium x 2:     $0.0416/時間 x 2 = $0.0832/時間
NAT Gateway:       $0.045/時間
-------------------------------------------
合計:              約$0.23/時間（約$170/月）
```

## トラブルシューティング

### クラスターに接続できない

```bash
# kubeconfigを更新
./script.sh kubeconfig my-cluster

# AWS認証を確認
aws sts get-caller-identity

# クラスター状態を確認
./script.sh cluster-show my-cluster
```

### ノードがNotReadyになる

```bash
# ノードの状態を確認
kubectl describe nodes

# システムポッドを確認
kubectl get pods -n kube-system

# VPC CNIの状態を確認
kubectl logs -n kube-system -l k8s-app=aws-node
```

### ポッドがPendingのまま

```bash
# ポッドの詳細を確認
kubectl describe pod <pod-name>

# ノードのリソースを確認
kubectl describe nodes | grep -A 5 "Allocated resources"

# ノードグループをスケールアップ
./script.sh nodegroup-scale my-cluster my-cluster-nodes 3
```

### LoadBalancerが作成されない

```bash
# サービスの状態を確認
kubectl describe svc <service-name>

# サブネットタグを確認（パブリックサブネット）
# kubernetes.io/role/elb = 1 が必要
```

## ベストプラクティス

### セキュリティ

1. **プライベートエンドポイント**を使用
2. **Security Group**でアクセスを制限
3. **IRSA**（IAM Roles for Service Accounts）を使用
4. **Secrets**はAWS Secrets Managerと連携

### 可用性

1. **マルチAZ**でノードを配置
2. **Pod Disruption Budget**を設定
3. **Cluster Autoscaler**を有効化

### コスト最適化

1. **Spot Instance**を活用
2. **Fargate**で一時的なワークロードを実行
3. 不要なクラスターは削除

## クリーンアップ

```bash
./script.sh destroy my-cluster
```

これにより以下が削除されます：
- EKSクラスター
- ノードグループ
- Fargateプロファイル
- VPC（サブネット、NAT Gateway等）
- IAMロール
- CloudWatchログ
