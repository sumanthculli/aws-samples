terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# SNS Topic for email notifications
resource "aws_sns_topic" "email_notifications" {
  name         = "${var.lambda_function_name}-notifications"
  display_name = "SES Email Processing Notifications"

  tags = var.tags
}

# SNS Topic Policy to allow SES to publish
resource "aws_sns_topic_policy" "email_notifications_policy" {
  arn = aws_sns_topic.email_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSESPublish"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.email_notifications.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# S3 Bucket for storing emails and PDFs
resource "aws_s3_bucket" "email_storage" {
  bucket        = var.email_bucket_name
  force_destroy = var.s3_force_destroy

  # Handle existing buckets gracefully
  lifecycle {
    ignore_changes = [bucket]
  }

  tags = var.tags
}



# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "email_storage_versioning" {
  bucket = aws_s3_bucket.email_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "email_storage_pab" {
  bucket = aws_s3_bucket.email_storage.id

  block_public_acls       = true
  block_public_policy     = true # Allow bucket policy for SES
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy to allow SES to write emails
resource "aws_s3_bucket_policy" "email_storage_policy" {
  bucket = aws_s3_bucket.email_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSESPuts"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.email_storage.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowSESPutsBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.email_storage.arn,
          "${aws_s3_bucket.email_storage.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.email_storage_pab]
}

# S3 Bucket lifecycle configuration for automatic cleanup
resource "aws_s3_bucket_lifecycle_configuration" "email_storage_lifecycle" {
  bucket = aws_s3_bucket.email_storage.id

  rule {
    id     = "cleanup_old_emails"
    status = "Enabled"

    # Clean up old email files after specified days
    expiration {
      days = var.email_retention_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    # Clean up old versions
    noncurrent_version_expiration {
      noncurrent_days = var.email_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.email_storage_versioning]
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.lambda_function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# S3 access policy for Lambda
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "S3AccessPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.email_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.email_storage.arn
      }
    ]
  })
}

# SES access policy for Lambda
resource "aws_iam_role_policy" "lambda_ses_policy" {
  name = "SESAccessPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.log_retention_days

  # Handle existing log groups gracefully
  lifecycle {
    ignore_changes = [name]
  }

  tags = var.tags
}

# Lambda function
resource "aws_lambda_function" "email_to_pdf" {
  filename      = var.lambda_zip_path
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      EMAIL_BUCKET   = aws_s3_bucket.email_storage.bucket
      INCLUDE_FOOTER = "true"
    }
  }

  # Handle existing Lambda functions gracefully
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_s3_policy,
    aws_iam_role_policy.lambda_ses_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_to_pdf.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.email_storage.arn
}

# SES Receipt Rule Set
resource "aws_ses_receipt_rule_set" "email_rule_set" {
  rule_set_name = "${var.ses_rule_name}-set"
}

# SES Receipt Rule
resource "aws_ses_receipt_rule" "email_rule" {
  name          = var.ses_rule_name
  rule_set_name = aws_ses_receipt_rule_set.email_rule_set.rule_set_name
  enabled       = true
  scan_enabled  = true

  recipients = [var.email_recipient]

  s3_action {
    bucket_name       = aws_s3_bucket.email_storage.bucket
    object_key_prefix = "emails/"
    topic_arn         = aws_sns_topic.email_notifications.arn
    position          = 1
  }

  depends_on = [
    aws_s3_bucket_policy.email_storage_policy,
    aws_sns_topic_policy.email_notifications_policy
  ]
}

# S3 Bucket Notification Configuration to trigger Lambda
resource "aws_s3_bucket_notification" "email_processing_trigger" {
  bucket = aws_s3_bucket.email_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.email_to_pdf.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "emails/"
    filter_suffix       = ".txt"
  }

  depends_on = [
    aws_lambda_permission.s3_invoke_lambda,
    aws_lambda_function.email_to_pdf
  ]
}
