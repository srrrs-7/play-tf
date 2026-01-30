# CLAUDE.md - AWS Batch

AWS Batch を作成するTerraformモジュール。コンピュート環境、ジョブキュー、ジョブ定義をサポート。

## Overview

このモジュールは以下のリソースを作成します:
- Batch Compute Environment (EC2, SPOT, Fargate)
- Batch Job Queue
- Batch Job Definition
- Batch Scheduling Policy (Fair Share)

## Key Resources

- `aws_batch_compute_environment.this` - コンピュート環境 (for_each)
- `aws_batch_job_queue.this` - ジョブキュー (for_each)
- `aws_batch_job_definition.this` - ジョブ定義 (for_each)
- `aws_batch_scheduling_policy.this` - スケジューリングポリシー (for_each)

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| compute_environments | list(object) | コンピュート環境設定リスト |
| job_queues | list(object) | ジョブキュー設定リスト |
| job_definitions | list(object) | ジョブ定義設定リスト |
| scheduling_policies | list(object) | スケジューリングポリシー設定リスト |
| tags | map(string) | リソースに付与する共通タグ |

### compute_environments object
| Field | Type | Description |
|-------|------|-------------|
| name | string | コンピュート環境名 |
| type | string | タイプ (MANAGED, UNMANAGED) |
| state | string | 状態 (ENABLED, DISABLED) |
| compute_resources | object | コンピュートリソース設定 |
| eks_configuration | object | EKS設定 (オプション) |

### compute_resources object
| Field | Type | Description |
|-------|------|-------------|
| type | string | タイプ (EC2, SPOT, FARGATE, FARGATE_SPOT) |
| max_vcpus | number | 最大vCPU数 |
| min_vcpus | number | 最小vCPU数 |
| subnets | list(string) | サブネットIDリスト |
| security_group_ids | list(string) | セキュリティグループIDリスト |

## Outputs

| Output | Description |
|--------|-------------|
| compute_environment_arns | コンピュート環境ARNマップ |
| compute_environment_names | コンピュート環境名リスト |
| compute_environment_status | コンピュート環境ステータスマップ |
| compute_environment_ecs_cluster_arns | ECSクラスターARNマップ |
| job_queue_arns | ジョブキューARNマップ |
| job_queue_names | ジョブキュー名リスト |
| job_definition_arns | ジョブ定義ARNマップ |
| job_definition_revisions | ジョブ定義リビジョンマップ |
| scheduling_policy_arns | スケジューリングポリシーARNマップ |

## Usage Example

```hcl
module "batch" {
  source = "../../modules/batch"

  compute_environments = [
    {
      name = "${var.project_name}-${var.environment}-fargate"
      compute_resources = {
        type      = "FARGATE"
        max_vcpus = 16
        subnets   = module.vpc.private_subnet_ids
        security_group_ids = [module.security_group.batch_sg_id]
      }
    }
  ]

  job_queues = [
    {
      name     = "${var.project_name}-${var.environment}-queue"
      priority = 1
      compute_environments = [
        {
          order                    = 1
          compute_environment_name = "${var.project_name}-${var.environment}-fargate"
        }
      ]
    }
  ]

  job_definitions = [
    {
      name                  = "${var.project_name}-${var.environment}-job"
      platform_capabilities = ["FARGATE"]
      container_properties = jsonencode({
        image      = "${aws_ecr_repository.app.repository_url}:latest"
        resourceRequirements = [
          { type = "VCPU", value = "1" },
          { type = "MEMORY", value = "2048" }
        ]
        executionRoleArn = aws_iam_role.batch_execution.arn
        jobRoleArn       = aws_iam_role.batch_job.arn
      })
      retry_strategy = {
        attempts = 3
      }
    }
  ]

  tags = var.tags
}
```

## Important Notes

- Fargateタイプは `platform_capabilities = ["FARGATE"]` が必須
- ジョブ定義の `container_properties` はJSON形式で指定
- コンピュート環境は `create_before_destroy` で安全に更新
- ジョブキューの優先度は0-1000の範囲
- SPOTインスタンス使用時は `bid_percentage` と `spot_iam_fleet_role` を設定
- Fair Shareスケジューリングで複数チーム間のリソース配分が可能
- EKS統合は `eks_configuration` で設定
