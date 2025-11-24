# AWS ECS Module

AWS ECS (Elastic Container Service) のクラスター、タスク定義、サービスを作成するためのTerraformモジュールです。

## 機能

- ECSクラスターの作成（オプション）
- タスク定義の作成（Fargate/EC2）
- ECSサービスの作成
- CloudWatch Logsグループの作成
- ロードバランサー（Target Group）との連携
- Capacity Provider Strategyのサポート

## 使用方法

```hcl
module "ecs" {
  source = "../modules/ecs"

  name = "my-app"
  
  # クラスターを新規作成する場合
  create_cluster = true
  cluster_name   = "my-cluster"

  # コンテナ定義
  container_definitions = jsonencode([
    {
      name  = "app"
      image = "nginx:latest"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/my-app"
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  cpu    = 256
  memory = 512
  
  subnet_ids         = ["subnet-12345678"]
  security_group_ids = ["sg-12345678"]
  
  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | サービス名（プレフィックス） | `string` | n/a | yes |
| create_cluster | クラスターを作成するか | `bool` | `true` | no |
| cluster_name | クラスター名 | `string` | `null` | no |
| cluster_id | 既存クラスターID (create_cluster=falseの場合) | `string` | `null` | no |
| container_definitions | コンテナ定義 (JSON) | `string` | n/a | yes |
| cpu | CPUユニット数 | `number` | `256` | no |
| memory | メモリ (MiB) | `number` | `512` | no |
| subnet_ids | サブネットIDリスト | `list(string)` | `[]` | no |
| security_group_ids | セキュリティグループIDリスト | `list(string)` | `[]` | no |
| desired_count | タスク数 | `number` | `1` | no |
| target_group_arn | ターゲットグループARN | `string` | `null` | no |
| container_name | LBに紐付けるコンテナ名 | `string` | `null` | no |
| container_port | LBに紐付けるコンテナポート | `number` | `null` | no |
| tags | リソースに付与するタグ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | クラスターID |
| cluster_name | クラスター名 |
| service_name | サービス名 |
| task_definition_arn | タスク定義ARN |
| log_group_name | ロググループ名 |
