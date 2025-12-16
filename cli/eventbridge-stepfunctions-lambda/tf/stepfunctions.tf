# =============================================================================
# Step Functions State Machine
# =============================================================================

resource "aws_sfn_state_machine" "order_workflow" {
  name     = var.stack_name
  role_arn = aws_iam_role.stepfunctions.arn
  type     = var.sfn_type

  definition = jsonencode({
    Comment = "Order processing workflow triggered by EventBridge"
    StartAt = "ValidateOrder"
    States = {
      ValidateOrder = {
        Type     = "Task"
        Resource = aws_lambda_function.functions["validate"].arn
        Next     = "ProcessPayment"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "OrderFailed"
          }
        ]
      }
      ProcessPayment = {
        Type     = "Task"
        Resource = aws_lambda_function.functions["payment"].arn
        Next     = "ShipOrder"
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            MaxAttempts     = 2
            IntervalSeconds = 1
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "OrderFailed"
          }
        ]
      }
      ShipOrder = {
        Type     = "Task"
        Resource = aws_lambda_function.functions["shipping"].arn
        Next     = "NotifyCustomer"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "OrderFailed"
          }
        ]
      }
      NotifyCustomer = {
        Type     = "Task"
        Resource = aws_lambda_function.functions["notify"].arn
        End      = true
      }
      OrderFailed = {
        Type  = "Fail"
        Error = "OrderProcessingFailed"
        Cause = "An error occurred during order processing"
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
  name              = "/aws/states/${var.stack_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-sfn-logs"
  })
}
