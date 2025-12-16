# =============================================================================
# Lambda Function
# =============================================================================

# デフォルトのLambdaコード
locals {
  default_lambda_code = <<-EOF
    const { S3Client, PutObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');

    const s3 = new S3Client({});
    const BUCKET = process.env.BUCKET_NAME;

    exports.handler = async (event) => {
        console.log('Scheduled event received:', JSON.stringify(event, null, 2));

        const timestamp = new Date().toISOString();
        const datePrefix = timestamp.slice(0, 10);

        // Generate sample data (simulating scheduled data collection)
        const data = {
            executionTime: timestamp,
            scheduleName: event.scheduleName || 'manual',
            metrics: {
                cpuUsage: Math.random() * 100,
                memoryUsage: Math.random() * 100,
                requestCount: Math.floor(Math.random() * 1000),
                errorRate: Math.random() * 5,
                latencyMs: Math.floor(Math.random() * 500)
            },
            environment: process.env.AWS_REGION,
            source: 'eventbridge-scheduler'
        };

        // Write data to S3
        const key = 'metrics/' + datePrefix + '/' + timestamp.replace(/[:.]/g, '-') + '.json';

        await s3.send(new PutObjectCommand({
            Bucket: BUCKET,
            Key: key,
            Body: JSON.stringify(data, null, 2),
            ContentType: 'application/json'
        }));

        console.log('Data written to s3://' + BUCKET + '/' + key);

        // List recent files
        const listResult = await s3.send(new ListObjectsV2Command({
            Bucket: BUCKET,
            Prefix: 'metrics/' + datePrefix + '/',
            MaxKeys: 10
        }));

        const fileCount = listResult.Contents?.length || 0;
        console.log('Total files today: ' + fileCount);

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Scheduled task completed',
                s3Key: key,
                timestamp: timestamp,
                filesWrittenToday: fileCount
            })
        };
    };
  EOF
}

# Lambdaアーカイブ
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_processor.zip"

  source {
    content  = local.default_lambda_code
    filename = "index.js"
  }
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.stack_name}-processor"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.data.id
      ENVIRONMENT = var.environment
      STACK_NAME  = var.stack_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-processor"
  })
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.stack_name}-processor"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-lambda-logs"
  })
}
