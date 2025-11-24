# AWS EC2 Module

AWS EC2インスタンスを作成するためのTerraformモジュールです。

## 機能

- EC2インスタンスの作成
- ルートボリュームのカスタマイズ
- EBSボリュームの追加
- IAMインスタンスプロファイルの設定
- ユーザーデータの設定
- メタデータオプションの設定（IMDSv2強制など）

## 使用方法

```hcl
module "ec2" {
  source = "../modules/ec2"

  name          = "my-instance"
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  subnet_id     = "subnet-12345678"
  
  vpc_security_group_ids = ["sg-12345678"]
  
  root_block_device = {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | インスタンス名（Nameタグ） | `string` | n/a | yes |
| ami | AMI ID | `string` | n/a | yes |
| instance_type | インスタンスタイプ | `string` | `"t3.micro"` | no |
| subnet_id | サブネットID | `string` | n/a | yes |
| vpc_security_group_ids | セキュリティグループIDのリスト | `list(string)` | `[]` | no |
| iam_instance_profile | IAMインスタンスプロファイル名 | `string` | `null` | no |
| user_data | ユーザーデータ | `string` | `null` | no |
| root_block_device | ルートボリューム設定 | `object` | `{}` | no |
| ebs_block_devices | 追加EBSボリューム設定 | `list(object)` | `[]` | no |
| metadata_options | メタデータオプション | `object` | `{}` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | インスタンスID |
| arn | インスタンスARN |
| public_ip | パブリックIP |
| private_ip | プライベートIP |
| availability_zone | アベイラビリティゾーン |
