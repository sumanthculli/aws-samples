provider "aws" {
  region = "us-west-2"
}

# Deploy Lambda with existing layer zip file
module "alarm_contributors_lambda" {
  source = "../modules/lambda-with-layer"

  function_name     = "alarm-contributors-function"
  lambda_handler    = "lambda_function.lambda_handler"
  runtime           = "python3.14"
  timeout           = 300
  memory_size       = 512
  lambda_source_dir = "${path.module}/../modules/lambda-with-layer/lambda"

  # Path to your existing layer zip file
  layer_zip_path = "${path.module}/boto3-layer.zip"
  layer_name     = "boto3-v142-latest"
  layer_description = "Latest boto3 library >= 1.42.0"

  # Compatible runtimes for the layer
  compatible_runtimes = ["python3.14", "python3.13", "python3.12"]

  # Use existing VPC resources
  subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1"
  ]
  
  security_group_ids = [
    "sg-0123456789abcdef0"
  ]

  # Environment variables
  environment_variables = {
    LOG_LEVEL = "INFO"
    REGION    = "us-west-2"
  }

  # CloudWatch Logs
  log_retention_days = 14

  # Additional IAM policies (optional)
  additional_policy_arns = []

  tags = {
    Environment = "production"
    Project     = "CloudWatch-Monitoring"
    ManagedBy   = "Terraform"
  }
}

# Outputs
output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.alarm_contributors_lambda.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.alarm_contributors_lambda.lambda_function_name
}

output "layer_arn" {
  description = "ARN of the Lambda Layer"
  value       = module.alarm_contributors_lambda.layer_arn
}

output "layer_version" {
  description = "Version of the Lambda Layer"
  value       = module.alarm_contributors_lambda.layer_version
}
