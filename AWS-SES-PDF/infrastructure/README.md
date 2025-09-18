# Infrastructure

This directory contains the Terraform configuration for the SES Email to PDF converter.

## Terraform Configuration

The Terraform configuration provides state management, modularity, and easy maintenance.

### Files

- `main.tf` - Main Terraform configuration with all resources
- `variables.tf` - Input variables and their defaults
- `outputs.tf` - Output values after deployment
- `terraform.tfvars.example` - Example configuration file

### Quick Start

1. **Copy and customize variables:**
   ```bash
   cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

2. **Deploy using the script:**
   ```bash
   ./scripts/deploy.sh
   ```

3. **Or deploy manually:**
   ```bash
   cd infrastructure
   terraform init
   terraform plan
   terraform apply
   ```

### Key Variables to Customize

- `email_bucket_name` - Must be globally unique S3 bucket name
- `email_recipient` - Email address that triggers the SES rule
- `aws_region` - AWS region for deployment
- `lambda_function_name` - Name for the Lambda function

### Importing Existing Resources

If you have existing AWS resources you want to manage with Terraform:

```bash
# Use terraform import for existing resources
terraform import aws_s3_bucket.email_storage your-existing-bucket-name
terraform import aws_lambda_function.email_to_pdf your-lambda-function-name
```

## Best Practices

1. **Store state remotely** (S3 + DynamoDB for locking)
2. **Use workspaces** for multiple environments
3. **Version control** your `.tfvars` files (without secrets)
4. **Use modules** for reusable components
5. **Run `terraform plan`** before applying changes

## Troubleshooting

### Common Issues

1. **Bucket name conflicts:**
   - S3 bucket names must be globally unique
   - Update `email_bucket_name` in terraform.tfvars

2. **Permission errors:**
   - Ensure AWS credentials have sufficient permissions
   - Check IAM policies for Terraform operations

3. **State conflicts:**
   - Use `terraform refresh` to sync state
   - Consider remote state for team collaboration

### Getting Help

- Check Terraform documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS Provider documentation: https://registry.terraform.io/providers/hashicorp/aws/latest
- Run `terraform validate` to check syntax
- Use `terraform plan` to preview changes