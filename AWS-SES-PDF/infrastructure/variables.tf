# AWS Region
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# S3 Bucket Name
variable "email_bucket_name" {
  description = "Name of the S3 bucket where SES stores incoming emails"
  type        = string
  default     = "ses-incoming-emails-bucket"
}

# Lambda Function Name
variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "ses-email-to-pdf-converter"
}

# SES Rule Name
variable "ses_rule_name" {
  description = "Name of the SES receipt rule"
  type        = string
  default     = "email-to-pdf-rule"
}

# Email Recipient
variable "email_recipient" {
  description = "Email address that will trigger the SES rule"
  type        = string
  default     = "incoming@example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email_recipient))
    error_message = "Email recipient must be a valid email address."
  }
}

# Lambda ZIP file path
variable "lambda_zip_path" {
  description = "Path to the Lambda deployment package ZIP file"
  type        = string
  default     = "../lambda-deployment-package.zip"
}

# CloudWatch Log Retention
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention values."
  }
}

# S3 Force Destroy
variable "s3_force_destroy" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects (useful for sandbox environments)"
  type        = bool
  default     = true
}

# Email Retention
variable "email_retention_days" {
  description = "Number of days to retain emails and PDFs in S3 before automatic deletion"
  type        = number
  default     = 90
  validation {
    condition     = var.email_retention_days > 0 && var.email_retention_days <= 3653
    error_message = "Email retention days must be between 1 and 3653 days (10 years)."
  }
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "SES-Email-to-PDF"
    Environment = "sandbox"
    ManagedBy   = "Terraform"
  }
}