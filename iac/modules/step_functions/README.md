# AWS Step Functions Module

AWS Step Functions ステートマシンを作成するためのTerraformモジュールです。

## 機能

- Step Functions ステートマシンの作成
- 実行ロール（IAM Role）の自動作成
- CloudWatch Logsによるログ出力設定
- X-Rayトレースの有効化
- 定義ファイル（ASL）の読み込み

## 使用方法

```hcl
module "step_functions" {
  source = "../modules/step_functions"

  name       = "my-state-machine"
  definition = file("${path.module}/definition.json")
  
  logging_configuration = {
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | ステートマシン名 | `string` | n/a | yes |
| definition | ステートマシン定義 (JSON string) | `string` | n/a | yes |
| type | ステートマシンタイプ (STANDARD or EXPRESS) | `string` | `"STANDARD"` | no |
| logging_configuration | ログ設定 | `object` | `{ include_execution_data = true, level = "ALL" }` | no |
| log_retention_days | ログ保持期間（日数） | `number` | `7` | no |
| tracing_enabled | X-Rayトレースを有効にするか | `bool` | `false` | no |
| policy_statements | 追加のIAMポリシーステートメント | `list(object)` | `[]` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| state_machine_arn | ステートマシンのARN |
| state_machine_name | ステートマシン名 |
| role_arn | 実行ロールのARN |
| role_name | 実行ロール名 |
