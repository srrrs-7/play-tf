# =============================================================================
# Step Functions State Machine
# =============================================================================

resource "aws_sfn_state_machine" "ecs_workflow" {
  name     = "${var.stack_name}-workflow"
  role_arn = aws_iam_role.stepfunctions.arn
  type     = var.sfn_type

  definition = jsonencode({
    Comment = "ECS Task orchestration workflow triggered by EventBridge"
    StartAt = "ValidateInput"
    States = {
      ValidateInput = {
        Type = "Pass"
        Parameters = {
          "taskType.$"  = "$.taskType"
          "payload.$"   = "$.payload"
          "timestamp.$" = "$$.State.EnteredTime"
        }
        Next = "DetermineTaskType"
      }
      DetermineTaskType = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.taskType"
            StringEquals  = "batch"
            Next          = "RunBatchTask"
          },
          {
            Variable      = "$.taskType"
            StringEquals  = "realtime"
            Next          = "RunRealtimeTask"
          }
        ]
        Default = "RunDefaultTask"
      }
      RunBatchTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = aws_ecs_cluster.main.arn
          TaskDefinition = aws_ecs_task_definition.main.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = local.subnet_ids
              SecurityGroups = [local.security_group_id]
              AssignPublicIp = "ENABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = "processor"
                Environment = [
                  { Name = "TASK_TYPE", Value = "batch" },
                  { "Name" = "PAYLOAD", "Value.$" = "States.JsonToString($.payload)" }
                ]
              }
            ]
          }
        }
        Next = "TaskCompleted"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "TaskFailed"
          }
        ]
      }
      RunRealtimeTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = aws_ecs_cluster.main.arn
          TaskDefinition = aws_ecs_task_definition.main.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = local.subnet_ids
              SecurityGroups = [local.security_group_id]
              AssignPublicIp = "ENABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = "processor"
                Environment = [
                  { Name = "TASK_TYPE", Value = "realtime" },
                  { "Name" = "PAYLOAD", "Value.$" = "States.JsonToString($.payload)" }
                ]
              }
            ]
          }
        }
        Next = "TaskCompleted"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "TaskFailed"
          }
        ]
      }
      RunDefaultTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = aws_ecs_cluster.main.arn
          TaskDefinition = aws_ecs_task_definition.main.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = local.subnet_ids
              SecurityGroups = [local.security_group_id]
              AssignPublicIp = "ENABLED"
            }
          }
        }
        Next = "TaskCompleted"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "TaskFailed"
          }
        ]
      }
      TaskCompleted = {
        Type = "Pass"
        Parameters = {
          status  = "COMPLETED"
          message = "ECS task completed successfully"
        }
        End = true
      }
      TaskFailed = {
        Type  = "Fail"
        Error = "ECSTaskFailed"
        Cause = "ECS task execution failed"
      }
    }
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-sfn"
  })
}

# =============================================================================
# CloudWatch Log Group for Step Functions
# =============================================================================

resource "aws_cloudwatch_log_group" "stepfunctions" {
  name              = "/aws/states/${var.stack_name}-workflow"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-sfn-logs"
  })
}
