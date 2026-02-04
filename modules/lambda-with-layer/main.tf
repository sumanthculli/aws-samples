terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

locals {
  lambda_zip_path = "${path.module}/lambda_function.zip"
}

# ==================== Lambda Layer ====================

# Create Lambda Layer from existing zip file
resource "aws_lambda_layer_version" "boto3_layer" {
  filename            = var.layer_zip_path
  layer_name          = var.layer_name
  description         = var.layer_description
  compatible_runtimes = var.compatible_runtimes
  
  source_code_hash = filebase64sha256(var.layer_zip_path)

  lifecycle {
    create_before_destroy = true
  }
}

# ==================== Lambda Function ====================

# Package Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = local.lambda_zip_path
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.function_name}-logs"
    }
  )
}

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach additional policies if provided
resource "aws_iam_role_policy_attachment" "additional_policies" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value
}

# Custom IAM policy for CloudWatch
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.function_name}-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmContributors",
          "cloudwatch:GetMetricData",
          "cloudwatch:DescribeInsightRules"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = var.lambda_handler
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers = [aws_lambda_layer_version.boto3_layer.arn]

  reserved_concurrent_executions = var.reserved_concurrent_executions

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]

  tags = merge(
    var.tags,
    {
      Name = var.function_name
    }
  )
}
