# Lambda Function ARN
output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.email_to_pdf.arn
}

# Lambda Function Name
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.email_to_pdf.function_name
}

# S3 Bucket Name
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing emails and PDFs"
  value       = aws_s3_bucket.email_storage.bucket
}

# S3 Bucket ARN
output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing emails and PDFs"
  value       = aws_s3_bucket.email_storage.arn
}

# SNS Topic ARN
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.email_notifications.arn
}

# SES Rule Set Name
output "ses_rule_set_name" {
  description = "Name of the SES receipt rule set"
  value       = aws_ses_receipt_rule_set.email_rule_set.rule_set_name
}

# SES Rule Name
output "ses_rule_name" {
  description = "Name of the SES receipt rule"
  value       = aws_ses_receipt_rule.email_rule.name
}

# CloudWatch Log Group
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}