# terraform.tfvars

# AWS Region
aws_region = "us-west-2"

# VPC and Networking
private_subnet_ids = [
  "subnet-xxxxx",
  "subnet-xxxx"
]
lambda_security_group_id = "sg-xxx"

# Secrets Manager
secret_arn = "arn:aws:secretsmanager:us-west-2:xxxxx:secret:my-rds-secret-AbCdEf"

# Lambda Function
lambda_function_name = "rds-postgres-rotation-function"
lambda_handler = "lambda_function.lambda_handler"
lambda_runtime = "python3.9"
lambda_timeout = 30
lambda_memory_size = 128

# IAM
lambda_role_name = "rds-postgres-rotation-lambda-role"
lambda_policy_name = "rds-postgres-rotation-lambda-policy"

# Secret Rotation
rotation_automatically_after_days = 30
