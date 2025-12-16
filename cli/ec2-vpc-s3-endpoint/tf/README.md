# EC2 + NAT Instance + VPC Endpoint + S3 Terraform Implementation

プライベートサブネット内のEC2インスタンスから、NAT Instance経由でインターネット（Git等）にアクセスし、VPC Endpoint経由でS3にアクセスするコスト最適化アーキテクチャのTerraform実装です。

## アーキテクチャ図

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ VPC (10.0.0.0/16)                                                               │
│                                                                                 │
│  ┌───────────────────────────────────┐  ┌──────────────────────────────────┐   │
│  │ Public Subnet (10.0.0.0/24)       │  │ Private Subnet (10.0.1.0/24)     │   │
│  │                                   │  │                                  │   │
│  │  ┌─────────────────────────┐      │  │  ┌────────────────┐             │   │
│  │  │ NAT Instance            │◄─────┼──┼──┤ EC2 Instance   │             │   │
│  │  │ (t4g.nano)              │      │  │  │ (t3.micro)     │             │   │
│  │  │                         │      │  │  │                │             │   │
│  │  │ - Public IP             │      │  │  │ - No Public IP │             │   │
│  │  │ - Source/Dest Check: No │      │  │  │ - SSM Agent    │             │   │
│  │  │ - IP Forwarding         │      │  │  │ - AWS CLI      │◄────────────┼───┼──► SSM
│  │  └───────────┬─────────────┘      │  │  └────────────────┘             │   │    (VPC Endpoint)
│  │              │                    │  │         │                       │   │
│  │              │ IGW                │  │         │ VPC Endpoints         │   │
│  │              ↓                    │  │         ↓                       │   │
│  └──────────────┼─────────────────────┘  │  ┌─────────────────────────┐    │   │
│                 │                        │  │ ● S3 (Gateway) - 無料    │────┼───┼──► S3
│            Internet                      │  │ ● SSM (Interface)       │    │   │
│           (Git, npm)                     │  │ ● SSMMessages           │    │   │
│                                          │  │ ● EC2Messages           │    │   │
│                                          │  └─────────────────────────┘    │   │
│                                          └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## コスト設計

NAT Gatewayの代わりにNAT Instanceを使用することで、**月額約$29の削減**を実現。

| リソース | タイプ | 料金 |
|---------|--------|------|
| NAT Instance | t4g.nano (ARM) | ~$3/月 |
| S3 VPC Endpoint | Gateway | **無料** |
| SSM VPC Endpoints | Interface × 3 | ~$22/月 |
| EC2 | t3.micro | 無料枠対象 |
| Internet Gateway | - | **無料** |

### 月額コスト比較

| 項目 | NAT Gateway | NAT Instance | 削減額 |
|-----|-------------|--------------|--------|
| 基本料金 | ~$32/月 | ~$3/月 | **$29/月** |
| データ転送 | $0.045/GB | 無料 | **追加削減** |

**年間削減額: 約$348**

## 前提条件

- Terraform >= 1.0.0
- AWS CLI v2（認証設定済み）
- Session Manager Plugin（CLI接続時のみ）

```bash
# Session Manager Plugin のインストール（macOS）
brew install --cask session-manager-plugin
```

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/ec2-vpc-s3-endpoint/tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集
```

### 2. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. EC2への接続

```bash
# 出力されたコマンドを使用
terraform output ssm_connect_command

# 実行
aws ssm start-session --target i-xxxxxxxxx
```

### 4. 動作確認（EC2内）

```bash
# インターネットアクセス確認（NAT Instance経由）
ping -c 3 8.8.8.8


# S3アクセス確認（VPC Endpoint経由）
aws s3 ls
aws s3 ls s3://your-bucket-name
```

### 5. リソース削除

```bash
terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── vpc.tf                     # VPC、サブネット、ルートテーブル
├── security-groups.tf         # セキュリティグループ
├── nat-instance.tf            # NAT Instance
├── vpc-endpoints.tf           # VPC Endpoints (S3, SSM)
├── iam.tf                     # IAMロール、インスタンスプロファイル
├── ec2.tf                     # EC2インスタンス
├── s3.tf                      # S3バケット
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `aws_region` | ap-northeast-1 | AWSリージョン |
| `nat_instance_type` | t4g.nano | NAT Instanceタイプ |
| `ec2_instance_type` | t3.micro | EC2タイプ |
| `create_ssm_endpoints` | true | SSM Endpoints作成（有料） |
| `s3_full_access` | false | S3フルアクセス許可 |

## 出力値

デプロイ後、以下の値が出力されます：

```bash
# 主要な出力値を確認
terraform output

# EC2接続コマンド
terraform output ssm_connect_command

# コスト概算
terraform output estimated_monthly_cost
```

## カスタマイズ

### SSM Endpointsを無効化（コスト削減）

Session Managerが不要な場合、月額~$22を削減できます：

```hcl
create_ssm_endpoints = false
```

> **注意**: SSM Endpointsを無効化すると、Session Manager経由でEC2に接続できなくなります。

### S3フルアクセスを有効化

```hcl
s3_full_access = true
```

### NAT Instanceタイプの変更

ARMが利用できないリージョンの場合：

```hcl
nat_instance_type        = "t3.nano"
nat_instance_type_is_arm = false
```

## トラブルシューティング

### Session Managerで接続できない

1. SSM Endpointsが作成されているか確認
2. EC2のIAMロールに`AmazonSSMManagedInstanceCore`がアタッチされているか確認
3. セキュリティグループでHTTPS(443)が許可されているか確認

```bash
# VPC Endpointsの状態確認
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].{ID:VpcEndpointId,Service:ServiceName,State:State}'
```

### インターネットにアクセスできない

1. NAT Instanceが起動しているか確認
2. プライベートサブネットのルートテーブルにNATルートがあるか確認
3. NAT InstanceのIP Forwarding/iptablesが正しく設定されているか確認

```bash
# NAT Instanceの状態確認
aws ec2 describe-instances --filters "Name=tag:Role,Values=NAT" --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name}'

# ルートテーブル確認
terraform output private_route_table_id
aws ec2 describe-route-tables --route-table-ids <route-table-id>
```

### NAT Instance詳細デバッグ

NAT Instance経由でcurlがタイムアウトする場合、NAT Instanceに接続して設定を確認してください：

```bash
# NAT InstanceにSession Manager経由で接続
aws ssm start-session --target <nat-instance-id>

# 設定ログを確認（起動時のスクリプト実行結果）
sudo cat /var/log/nat-setup.log

# IP Forwardingが有効か確認（1であるべき）
cat /proc/sys/net/ipv4/ip_forward

# iptables NAT ルールを確認（MASQUERADEルールがあるべき）
sudo iptables -t nat -L -v -n

# iptables FORWARD ルールを確認（ポリシーがACCEPTであるべき）
sudo iptables -L FORWARD -v -n

# ネットワークインターフェースを確認
ip addr show

# ルートテーブルを確認
ip route show
```

#### 正常な状態の例

```bash
# IP Forward
$ cat /proc/sys/net/ipv4/ip_forward
1

# NAT ルール（ens5またはeth0にMASQUERADEがある）
$ sudo iptables -t nat -L POSTROUTING -v -n
Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MASQUERADE  all  --  *      ens5    0.0.0.0/0            0.0.0.0/0

# FORWARD ポリシー
$ sudo iptables -L FORWARD -v -n
Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
```

#### 手動で修正する場合

```bash
# IP Forwarding を有効化
sudo sysctl -w net.ipv4.ip_forward=1

# プライマリインターフェースを検出
PRIMARY_IF=$(ip route | grep default | awk '{print $5}')
echo "Primary interface: $PRIMARY_IF"

# iptablesをインストール（Amazon Linux 2023）
sudo dnf install -y iptables-nft iptables-services

# NAT設定
sudo iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE
sudo iptables -P FORWARD ACCEPT

# 設定を永続化
sudo mkdir -p /etc/sysconfig
sudo iptables-save | sudo tee /etc/sysconfig/iptables
```

#### NAT Instanceを再作成する場合

```bash
# Terraformで再作成
terraform taint 'aws_instance.nat[0]'
terraform apply

# 起動後2-3分待ってからテスト
```

### S3にアクセスできない

1. S3 Gateway Endpointが作成されているか確認
2. IAMロールにS3権限があるか確認

```bash
# S3 Endpoint確認
terraform output s3_endpoint_id
```

## CLIスクリプトとの対応

このTerraform実装は、`../script.sh`のCLI実装と同等の機能を提供します：

| CLI コマンド | Terraform リソース |
|-------------|-------------------|
| `deploy` | `terraform apply` |
| `destroy` | `terraform destroy` |
| `status` | `terraform output` |
| `vpc-create` | `vpc.tf` |
| `nat-create` | `nat-instance.tf` |
| `endpoint-s3-create` | `vpc-endpoints.tf` (S3) |
| `endpoint-ssm-create` | `vpc-endpoints.tf` (SSM) |
| `sg-create` | `security-groups.tf` |
| `role-create` | `iam.tf` |
| `ec2-create` | `ec2.tf` |
| `s3-create` | `s3.tf` |

## 関連ドキュメント

- [VPC Endpoints for Amazon S3](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [NAT instances](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
