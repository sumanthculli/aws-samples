variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_handler" {
  description = "Lambda function handler"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.14"
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 300
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 512
}

variable "subnet_ids" {
  description = "List of subnet IDs for Lambda function"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda function"
  type        = list(string)
}

variable "environment_variables" {
  description = "Environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

variable "layer_zip_path" {
  description = "Path to the Lambda layer zip file"
  type        = string
}

variable "layer_name" {
  description = "Name of the Lambda Layer"
  type        = string
  default     = "boto3-latest"
}

variable "layer_description" {
  description = "Description of the Lambda Layer"
  type        = string
  default     = "Latest boto3 library (>= 1.42.0)"
}

variable "lambda_source_dir" {
  description = "Directory containing Lambda function code"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for Lambda"
  type        = number
  default     = -1
}

variable "additional_policy_arns" {
  description = "Additional IAM policy ARNs to attach to Lambda role"
  type        = list(string)
  default     = []
}

variable "compatible_runtimes" {
  description = "List of compatible runtimes for the layer"
  type        = list(string)
  default     = ["python3.14", "python3.13", "python3.12"]
}
