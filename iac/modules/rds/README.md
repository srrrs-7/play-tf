# AWS RDS Module

AWS RDSインスタンスを作成するためのTerraformモジュールです。

## 機能

- RDSインスタンスの作成
- DBサブネットグループの作成（オプション）
- DBパラメータグループの作成（オプション）
- DBオプショングループの作成（オプション）
- マルチAZ配置のサポート
- バックアップ、メンテナンスウィンドウの設定
- Performance Insightsの設定
- 拡張モニタリングの設定
- ログのエクスポート設定

## 使用方法

```hcl
module "rds" {
  source = "../modules/rds"

  identifier = "my-db"
  
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  
  db_name  = "mydb"
  username = "admin"
  password = "password123" # Secrets Managerの使用を推奨
  
  vpc_security_group_ids = ["sg-12345678"]
  
  create_db_subnet_group = true
  subnet_ids             = ["subnet-1", "subnet-2"]
  db_subnet_group_name   = "my-db-subnet-group"
  
  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| identifier | インスタンス識別子 | `string` | n/a | yes |
| engine | エンジン (mysql, postgres, etc.) | `string` | n/a | yes |
| engine_version | エンジンバージョン | `string` | n/a | yes |
| instance_class | インスタンスクラス | `string` | n/a | yes |
| allocated_storage | ストレージ容量 (GB) | `number` | n/a | yes |
| username | マスターユーザー名 | `string` | n/a | yes |
| password | マスターパスワード | `string` | n/a | yes |
| db_name | データベース名 | `string` | `null` | no |
| multi_az | マルチAZ配置 | `bool` | `false` | no |
| storage_encrypted | ストレージ暗号化 | `bool` | `true` | no |
| create_db_subnet_group | サブネットグループを作成するか | `bool` | `false` | no |
| subnet_ids | サブネットIDリスト | `list(string)` | `[]` | no |
| create_db_parameter_group | パラメータグループを作成するか | `bool` | `false` | no |
| parameters | パラメータリスト | `list(object)` | `[]` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | インスタンスID |
| arn | インスタンスARN |
| address | アドレス |
| endpoint | エンドポイント |
| port | ポート |
