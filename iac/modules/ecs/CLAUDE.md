# CLAUDE.md - Amazon ECS

Amazon ECS クラスター、サービス、タスク定義を作成するTerraformモジュール。Fargate対応。

## Overview

このモジュールは以下のリソースを作成します:
- ECS Cluster (オプション)
- ECS Task Definition
- ECS Service
- CloudWatch Log Group

## Key Resources

- `aws_ecs_cluster.this` - ECSクラスター
- `aws_ecs_task_definition.this` - タスク定義
- `aws_ecs_service.this` - ECSサービス
- `aws_cloudwatch_log_group.this` - ログ出力先

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | リソース名プレフィックス |
| create_cluster | bool | ECSクラスターを作成するか (default: true) |
| cluster_name | string | クラスター名 (未指定時は自動生成) |
| cluster_id | string | 既存クラスターID (create_cluster=false時) |
| container_insights | bool | Container Insightsを有効にするか (default: true) |
| container_definitions | string | コンテナ定義JSON |
| requires_compatibilities | list(string) | 起動タイプ (default: ["FARGATE"]) |
| network_mode | string | ネットワークモード (default: awsvpc) |
| cpu | number | タスクCPUユニット (default: 256) |
| memory | number | タスクメモリMiB (default: 512) |
| execution_role_arn | string | タスク実行ロールARN |
| task_role_arn | string | タスクロールARN |
| operating_system_family | string | OS (default: LINUX) |
| cpu_architecture | string | CPUアーキテクチャ (default: X86_64) |
| desired_count | number | タスク数 (default: 1) |
| subnet_ids | list(string) | サブネットIDリスト |
| security_group_ids | list(string) | セキュリティグループIDリスト |
| assign_public_ip | bool | パブリックIP割り当て (default: false) |
| target_group_arn | string | ALBターゲットグループARN |
| container_name | string | ロードバランサー連携コンテナ名 |
| container_port | number | ロードバランサー連携ポート |
| capacity_provider_strategy | list(object) | キャパシティプロバイダー戦略 |
| create_log_group | bool | ログループを作成するか (default: true) |
| log_retention_days | number | ログ保持期間 (default: 7) |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | ECSサービスID |
| arn | タスク定義ARN |
| name | ECSサービス名 |
| cluster_id | ECSクラスターID |
| cluster_name | ECSクラスター名 |
| task_definition_arn | タスク定義ARN |
| log_group_name | CloudWatchロググループ名 |

## Usage Example

```hcl
module "ecs" {
  source = "../../modules/ecs"

  name         = "${var.project_name}-${var.environment}-app"
  cluster_name = "${var.project_name}-${var.environment}-cluster"

  cpu    = 512
  memory = 1024

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${module.ecr.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.project_name}-${var.environment}-app"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  desired_count      = 2
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_group.ecs_sg_id]

  target_group_arn = module.alb.target_group_arns["app"]
  container_name   = "app"
  container_port   = 8080

  tags = var.tags
}
```

## Important Notes

- Fargate使用時は `network_mode = "awsvpc"` が必須
- `container_definitions` はJSON形式で指定
- `execution_role_arn` はECRプルとログ出力に必要
- `task_role_arn` はコンテナからのAWSサービスアクセスに必要
- `desired_count` は lifecycle で ignore_changes 設定済み (Auto Scaling対応)
- Container Insightsでコンテナレベルのメトリクス取得
- ARM64対応は `cpu_architecture = "ARM64"` で設定 (Graviton2)
- ログは `/ecs/{name}` 形式のロググループに出力
