# EC2 + NAT Instance + VPC Endpoint + S3 アーキテクチャ

プライベートサブネット内のEC2インスタンスから、NAT Instance経由でインターネット（Git等）にアクセスし、VPC Endpoint経由でS3にアクセスするコスト最適化アーキテクチャです。
Session Managerを使用してSSHなし・プライベートIPのみでEC2に接続できます。

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
│  │  │ - IP Forwarding         │      │  │  │ - AWS CLI      │             │   │
│  │  └───────────┬─────────────┘      │  │  │ - Git          │◄────────────┼───┼──► SSM
│  │              │                    │  │  └────────────────┘             │   │    (VPC Endpoint)
│  │              │ IGW                │  │         │                       │   │
│  │              ↓                    │  │         │ VPC Endpoints         │   │
│  └──────────────┼─────────────────────┘  │         ↓                       │   │
│                 │                        │  ┌─────────────────────────┐    │   │
│            Internet                      │  │ ● S3 (Gateway)          │────┼───┼──► S3
│           (Git, npm)                     │  │ ● SSM (Interface)       │    │   │
│                                          │  │ ● SSMMessages           │    │   │
│                                          │  │ ● EC2Messages           │    │   │
│                                          │  └─────────────────────────┘    │   │
│                                          │                                 │   │
│                                          │  Private Route Table            │   │
│                                          │  ┌────────────────────────────┐  │   │
│                                          │  │ 0.0.0.0/0 → NAT Instance   │  │   │
│                                          │  │ pl-xxx (S3) → S3 Endpoint  │  │   │
│                                          │  └────────────────────────────┘  │   │
│                                          └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘

     ▲
     │ Session Manager
     │ (AWS Console / CLI)
     │
┌────┴─────┐
│ Operator │
└──────────┘
```

## コスト設計

このアーキテクチャはコスト最小化を重視しています。NAT Gatewayの代わりにNAT Instanceを使用することで、**月額約$29の削減**を実現します。

| リソース | タイプ | 料金 |
|---------|--------|------|
| NAT Instance | t4g.nano (ARM) | ~$3.04/月 |
| S3 VPC Endpoint | Gateway | **無料** |
| SSM VPC Endpoints | Interface × 3 | ~$0.01/時間/エンドポイント |
| EC2 | t3.micro | 無料枠対象（750時間/月） |
| Internet Gateway | - | **無料** |
| NAT Gateway | **不使用** | $0（代わりにNAT Instance） |

### 月額コスト概算（無料枠除外時）

- NAT Instance (t4g.nano): ~$3/月
- VPC Interface Endpoints: ~$22/月（3エンドポイント × $0.01/時間 × 720時間）
- EC2 t3.micro: ~$8/月
- S3: 使用量に応じた従量課金
- **合計: ~$33/月**

### NAT Gatewayとのコスト比較

| 項目 | NAT Gateway | NAT Instance | 削減額 |
|-----|-------------|--------------|--------|
| 基本料金 | ~$32/月 | ~$3/月 | **$29/月** |
| データ転送費 | $0.045/GB | 無料 | **追加削減** |
| 可用性 | AWS管理 | 手動管理 | - |

**年間削減額: 約$348**

## 前提条件

- AWS CLI v2 がインストールされていること
- AWS認証情報が設定されていること
- Session Manager Plugin がインストールされていること（CLI経由でEC2に接続する場合）

```bash
# Session Manager Plugin のインストール（CLI接続用）
# macOS
brew install --cask session-manager-plugin

# Linux (Debian/Ubuntu)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

**注**: ブラウザから接続する場合は、Session Manager Pluginのインストールは不要です。

## クイックスタート

### フルスタックデプロイ

```bash
# すべてのリソースを一括作成
./script.sh deploy my-stack

# バケット名を指定する場合
./script.sh deploy my-stack my-custom-bucket
```

デプロイされるリソース:
1. VPC（パブリック＆プライベートサブネット付き）
2. Internet Gateway
3. NAT Instance（t4g.nano）
4. セキュリティグループ（NAT用 + EC2用）
5. S3 Gateway VPC Endpoint
6. SSM Interface VPC Endpoints（ssm, ssmmessages, ec2messages）
7. IAMロール（SSM + S3権限）
8. EC2インスタンス
9. S3バケット

### EC2への接続

#### 方法1: CLIから接続（推奨）

```bash
# スクリプト経由で接続
./script.sh ec2-connect i-1234567890abcdef0

# または直接AWS CLIを使用
aws ssm start-session --target i-1234567890abcdef0
```

#### 方法2: ブラウザから接続（プラグイン不要）

1. [AWS Systems Manager コンソール](https://console.aws.amazon.com/systems-manager/)を開く
2. 左メニューから「Session Manager」を選択
3. 「セッションを開始」ボタンをクリック
4. 対象のEC2インスタンスを選択
5. 「セッションを開始」ボタンをクリック

ブラウザ内でターミナルが開き、EC2に接続できます。Session Manager Pluginのインストールは不要です。

### インターネットアクセスの確認（EC2内部から）

EC2に接続後、NAT Instance経由でインターネットにアクセスできることを確認：

```bash
# 接続確認
ping -c 3 8.8.8.8

# HTTPSアクセス確認
curl -I https://github.com

# Gitリポジトリのクローン
git clone https://github.com/torvalds/linux.git

# パッケージ更新（yum/apt）
sudo yum update -y
```

### S3アクセスの確認（EC2内部から）

VPC Gateway Endpoint経由でS3にアクセス（NAT Instance経由ではないため無料）：

```bash
# S3バケット一覧
aws s3 ls

# 特定バケットの内容確認
aws s3 ls s3://my-stack-bucket-xxxxx

# ファイルアップロード
echo "test" > test.txt
aws s3 cp test.txt s3://my-stack-bucket-xxxxx/
```

### ステータス確認

```bash
# スタックのステータスを確認
./script.sh status my-stack

# 全リソースのステータスを確認
./script.sh status
```

### リソースの削除

```bash
# すべてのリソースを一括削除
./script.sh destroy my-stack
```

## コマンドリファレンス

### フルスタック操作

| コマンド | 説明 |
|---------|------|
| `deploy <stack-name> [bucket-name]` | 全リソースをデプロイ（NAT Instance含む） |
| `destroy <stack-name>` | 全リソースを削除 |
| `status [stack-name]` | ステータス確認 |

### VPC操作

| コマンド | 説明 |
|---------|------|
| `vpc-create <name> [cidr]` | VPC、パブリックサブネット、プライベートサブネット、IGWを作成 |
| `vpc-delete <vpc-id>` | VPCと関連リソースを削除 |
| `vpc-list` | VPC一覧を表示 |

### NAT Instance操作

| コマンド | 説明 |
|---------|------|
| `nat-create <name> <subnet-id> <sg-id> [type]` | NAT Instanceを作成（デフォルト: t4g.nano） |
| `nat-delete <instance-id>` | NAT Instanceを削除 |
| `nat-list` | NAT Instance一覧を表示 |
| `nat-sg-create <name> <vpc-id>` | NAT Instance用セキュリティグループを作成 |

### VPC Endpoint操作

| コマンド | 説明 |
|---------|------|
| `endpoint-s3-create <vpc-id> <route-table-id>` | S3 Gateway Endpointを作成 |
| `endpoint-ssm-create <vpc-id> <subnet-id> <sg-id>` | SSM Interface Endpointsを作成 |
| `endpoint-delete <endpoint-id>` | VPC Endpointを削除 |
| `endpoint-list [vpc-id]` | VPC Endpoint一覧を表示 |

### セキュリティグループ操作

| コマンド | 説明 |
|---------|------|
| `sg-create <name> <vpc-id>` | EC2用セキュリティグループを作成 |
| `sg-delete <sg-id>` | セキュリティグループを削除 |

### IAMロール操作

| コマンド | 説明 |
|---------|------|
| `role-create <name>` | EC2用IAMロールを作成（SSM + S3権限） |
| `role-delete <name>` | IAMロールを削除 |

### EC2操作

| コマンド | 説明 |
|---------|------|
| `ec2-create <name> <subnet-id> <sg-id> <profile>` | EC2インスタンスを作成 |
| `ec2-delete <instance-id>` | EC2インスタンスを終了 |
| `ec2-list` | EC2インスタンス一覧を表示 |
| `ec2-connect <instance-id>` | Session Manager経由で接続 |

### S3操作

| コマンド | 説明 |
|---------|------|
| `s3-create <bucket-name>` | S3バケットを作成 |
| `s3-delete <bucket-name>` | S3バケットを削除 |
| `s3-list` | S3バケット一覧を表示 |

## 手動デプロイ（ステップバイステップ）

個別にリソースを作成する場合:

```bash
# 1. VPCを作成（パブリック＆プライベートサブネット、IGW含む）
./script.sh vpc-create my-stack

# 出力されるVPC ID、パブリックサブネットID、プライベートサブネットID、ルートテーブルIDをメモ

# 2. NAT Instance用セキュリティグループを作成
./script.sh nat-sg-create my-stack-nat-sg vpc-xxxxx

# 3. NAT Instanceを作成（パブリックサブネットに配置）
./script.sh nat-create my-stack-nat subnet-public-xxxxx sg-nat-xxxxx

# 出力されるNAT Instance IDをメモ

# 4. プライベートサブネットのルートテーブルにNATルートを追加
aws ec2 create-route \
    --route-table-id rtb-private-xxxxx \
    --destination-cidr-block 0.0.0.0/0 \
    --instance-id i-nat-xxxxx

# 5. EC2用セキュリティグループを作成
./script.sh sg-create my-stack-sg vpc-xxxxx

# 6. S3 Gateway Endpointを作成（無料）
./script.sh endpoint-s3-create vpc-xxxxx rtb-private-xxxxx

# 7. SSM Interface Endpointsを作成
./script.sh endpoint-ssm-create vpc-xxxxx subnet-private-xxxxx sg-xxxxx

# 8. IAMロールを作成
./script.sh role-create my-stack-role

# 9. S3バケットを作成
./script.sh s3-create my-bucket

# 10. EC2インスタンスを作成（プライベートサブネットに配置）
./script.sh ec2-create my-stack-ec2 subnet-private-xxxxx sg-xxxxx my-stack-role-profile
```

## セキュリティ設計

### ネットワークセキュリティ

- **EC2**: プライベートサブネットに配置（パブリックIPなし）
- **NAT Instance**: パブリックサブネットに配置（パブリックIP有り）
  - Source/Destination Checkを無効化（NAT機能のため必要）
  - プライベートサブネットからのHTTP/HTTPS通信のみ許可
- **Internet Gateway**: パブリックサブネットのみ接続
- **ルーティング**:
  - プライベートサブネット: `0.0.0.0/0` → NAT Instance（インターネット用）
  - プライベートサブネット: `pl-xxx (S3)` → S3 Gateway Endpoint（S3専用）
- **セキュリティグループ**:
  - EC2: VPC内部からのHTTPS（443）のみ許可（VPC Endpoint用）
  - NAT Instance: VPC内部からのHTTP（80）、HTTPS（443）、ICMP（ping）を許可

### セキュリティグループ詳細

#### NAT Instance用セキュリティグループ

| 方向 | プロトコル | ポート | ソース/宛先 | 用途 |
|------|-----------|--------|------------|------|
| インバウンド | TCP | 80 | 10.0.0.0/16 (VPC CIDR) | パッケージ更新 (yum/apt) |
| インバウンド | TCP | 443 | 10.0.0.0/16 (VPC CIDR) | Git, npm, HTTPS通信 |
| インバウンド | ICMP | All | 10.0.0.0/16 (VPC CIDR) | ping疎通確認 |
| アウトバウンド | All | All | 0.0.0.0/0 | インターネットへの通信 |

#### EC2用セキュリティグループ

| 方向 | プロトコル | ポート | ソース/宛先 | 用途 |
|------|-----------|--------|------------|------|
| インバウンド | TCP | 443 | 10.0.0.0/16 (VPC CIDR) | VPC Endpoint通信 |
| アウトバウンド | All | All | 0.0.0.0/0 | NAT Instance、VPC Endpoint経由の通信 |

**注**: EC2のアウトバウンドはデフォルトで全て許可されており、実際の通信はNAT InstanceとVPC Endpointのセキュリティグループで制御されます。

### IAM権限

EC2インスタンスに付与される権限:
- `AmazonSSMManagedInstanceCore`: Session Manager接続に必要
- `AmazonS3ReadOnlyAccess`: S3読み取りアクセス

書き込み権限が必要な場合は、`role-create`後に追加のポリシーをアタッチしてください:

```bash
aws iam attach-role-policy \
    --role-name my-stack-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### データ保護

- S3バケットはパブリックアクセスをブロック
- S3バケットはバージョニング有効
- EC2インスタンスはIMDSv2を強制（HttpTokens=required）

## トラブルシューティング

### Session Managerで接続できない

1. SSM Agentが起動しているか確認（Amazon Linux 2023は標準搭載）
2. VPC Endpointsが正常に作成されているか確認
3. セキュリティグループでHTTPS（443）が許可されているか確認
4. IAMロールに`AmazonSSMManagedInstanceCore`がアタッチされているか確認

```bash
# VPC Endpointのステータス確認
./script.sh endpoint-list vpc-xxxxx

# EC2インスタンスがSSMに登録されているか確認
aws ssm describe-instance-information
```

### インターネットにアクセスできない

1. NAT Instanceが起動しているか確認
2. NAT InstanceのSource/Destination Checkが無効になっているか確認
3. プライベートサブネットのルートテーブルに`0.0.0.0/0 → NAT Instance`のルートがあるか確認
4. NAT Instanceのセキュリティグループで必要なポート（80, 443）が許可されているか確認

```bash
# NAT Instanceのステータス確認
./script.sh nat-list

# Source/Destination Checkの確認
aws ec2 describe-instances --instance-ids i-nat-xxxxx \
    --query 'Reservations[0].Instances[0].SourceDestCheck'

# ルートテーブルの確認
aws ec2 describe-route-tables --route-table-ids rtb-private-xxxxx

# NAT Instance内でのトラブルシューティング（NAT Instanceに接続して実行）
# IPフォワーディングが有効か確認
sysctl net.ipv4.ip_forward

# iptablesルールの確認
sudo iptables -t nat -L -n -v
```

### S3にアクセスできない

1. S3 Gateway Endpointがルートテーブルに追加されているか確認
2. IAMロールにS3権限があるか確認

```bash
# ルートテーブルの確認
aws ec2 describe-route-tables --route-table-ids rtb-xxxxx

# IAMロールのポリシー確認
aws iam list-attached-role-policies --role-name my-stack-role
```

### EC2インスタンスが起動しない

1. サブネットのCIDRブロックが正しいか確認
2. セキュリティグループがVPCに存在するか確認
3. インスタンスプロファイルが存在するか確認

### NAT Instanceが起動しない（ARM/t4g系）

1. 選択したリージョンでt4g.nanoが利用可能か確認
2. t4g.nanoが利用できない場合は、t3.nanoを使用:

```bash
# t3.nanoでNAT Instanceを作成
./script.sh nat-create my-stack-nat subnet-public-xxxxx sg-nat-xxxxx t3.nano
```

## 関連ドキュメント

- [VPC Endpoints for Amazon S3](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [VPC Endpoint pricing](https://aws.amazon.com/privatelink/pricing/)
- [NAT instances](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html)
- [Comparison of NAT instances and NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-comparison.html)
- [EC2 pricing (for NAT Instance cost)](https://aws.amazon.com/ec2/pricing/on-demand/)
