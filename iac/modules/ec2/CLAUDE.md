# CLAUDE.md - Amazon EC2

Amazon EC2 インスタンスを作成するTerraformモジュール。EBSボリューム、メタデータオプション対応。

## Overview

このモジュールは以下のリソースを作成します:
- EC2 Instance
- Root Block Device (EBS)
- Additional EBS Block Devices

## Key Resources

- `aws_instance.this` - EC2インスタンス本体

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | インスタンス名 |
| ami | string | AMI ID |
| instance_type | string | インスタンスタイプ (default: t3.micro) |
| subnet_id | string | サブネットID |
| vpc_security_group_ids | list(string) | セキュリティグループIDリスト |
| iam_instance_profile | string | IAMインスタンスプロファイル名 |
| user_data | string | ユーザーデータスクリプト |
| user_data_replace_on_change | bool | ユーザーデータ変更時に再作成するか (default: false) |
| disable_api_termination | bool | 終了保護を有効にするか (default: false) |
| monitoring | bool | 詳細モニタリングを有効にするか (default: false) |
| root_block_device | object | ルートブロックデバイス設定 |
| ebs_block_devices | list(object) | 追加EBSブロックデバイス設定 |
| metadata_options | object | インスタンスメタデータオプション |
| tags | map(string) | リソースに付与する共通タグ |

### root_block_device object
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| volume_type | string | gp3 | ボリュームタイプ |
| volume_size | number | 8 | ボリュームサイズ (GB) |
| delete_on_termination | bool | true | 終了時に削除するか |
| encrypted | bool | true | 暗号化するか |
| kms_key_id | string | null | 暗号化用KMSキーID |

### metadata_options object
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| http_endpoint | string | enabled | メタデータエンドポイント |
| http_tokens | string | required | IMDSv2必須 |
| http_put_response_hop_limit | number | 1 | ホップ制限 |
| instance_metadata_tags | string | enabled | タグのメタデータアクセス |

## Outputs

| Output | Description |
|--------|-------------|
| id | インスタンスID |
| arn | インスタンスARN |
| public_ip | パブリックIPアドレス |
| private_ip | プライベートIPアドレス |
| availability_zone | アベイラビリティゾーン |

## Usage Example

```hcl
module "ec2" {
  source = "../../modules/ec2"

  name          = "${var.project_name}-${var.environment}-web"
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.small"
  subnet_id     = module.vpc.private_subnet_ids[0]

  vpc_security_group_ids = [module.security_group.ec2_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device = {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  ebs_block_devices = [
    {
      device_name = "/dev/sdf"
      volume_type = "gp3"
      volume_size = 100
      encrypted   = true
    }
  ]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
  EOF

  tags = var.tags
}
```

## Important Notes

- IMDSv2 (http_tokens = required) がデフォルトで有効
- `ami` と `user_data` は lifecycle で ignore_changes 設定済み
- ルートボリュームはデフォルトで暗号化 (encrypted = true)
- 追加EBSボリュームも同様にデフォルト暗号化
- Session Manager使用時はIAMロールに `AmazonSSMManagedInstanceCore` ポリシーを付与
- 終了保護は本番環境で `disable_api_termination = true` を推奨
- 詳細モニタリングは1分間隔のメトリクス (追加料金あり)
