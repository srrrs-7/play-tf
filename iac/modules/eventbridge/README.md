# AWS EventBridge Module

AWS EventBridge (CloudWatch Events) ルールとターゲットを作成するためのTerraformモジュールです。

## 機能

- EventBridgeルールの作成（スケジュールまたはイベントパターン）
- ターゲットの設定（複数可）
- IAMロールの自動作成（必要な場合）
- デッドレターキューの設定

## 使用方法

```hcl
module "eventbridge" {
  source = "../modules/eventbridge"

  name        = "my-scheduled-rule"
  description = "Trigger Lambda every hour"
  schedule_expression = "rate(1 hour)"

  targets = [
    {
      arn = module.lambda.function_arn
      target_id = "my-lambda-target"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | ルール名 | `string` | n/a | yes |
| description | ルールの説明 | `string` | `""` | no |
| schedule_expression | スケジュール式 (e.g., cron(0 20 * * ? *) or rate(5 minutes)) | `string` | `null` | no |
| event_pattern | イベントパターン (JSON) | `string` | `null` | no |
| is_enabled | ルールを有効にするか | `bool` | `true` | no |
| targets | ターゲットのリスト | `list(object)` | `[]` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| rule_arn | EventBridgeルールのARN |
| rule_name | EventBridgeルール名 |
