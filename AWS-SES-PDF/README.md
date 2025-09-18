# AWS SES Email to PDF Converter

A complete serverless solution that automatically converts incoming SES emails to professionally formatted PDF documents using AWS Lambda, S3, and SES receipt rules.

## 🏗️ Architecture

```
Incoming Email → SES → S3 Bucket → Lambda Trigger → PDF Generation → S3 Storage
```

## ✨ Features

- **Automatic Processing**: Converts emails to PDF as soon as they arrive
- **Professional Formatting**: Clean, readable PDFs with proper styling
- **Complete Email Capture**: Preserves metadata, content, and attachment info
- **HTML & Text Support**: Handles both HTML and plain text emails
- **Scalable**: Serverless architecture handles any volume
- **Cost-Effective**: Pay only for what you use
- **Secure**: IAM roles with least-privilege access

## 📁 Project Structure

```
AWS-SES-PDF/
├── src/                          # Source code
│   ├── lambda_function.py        # Main Lambda function
│   └── requirements.txt          # Python dependencies
├── infrastructure/               # Infrastructure as Code (Terraform)
│   ├── main.tf                  # Terraform configuration
│   ├── variables.tf             # Terraform variables
│   ├── outputs.tf               # Terraform outputs
│   └── terraform.tfvars.example # Terraform configuration example
├── scripts/                      # Deployment and management scripts
│   ├── deploy.sh                # Terraform deployment script
│   ├── test.sh                  # Comprehensive testing script
│   └── cleanup.sh               # Resource cleanup script
├── tests/                        # Test files and sample data
│   └── sample-email.txt         # Sample email for testing
└── README.md                    # This file
```

## 🚀 Quick Start

### Prerequisites

Before you begin, ensure you have:

- **AWS CLI** configured with appropriate permissions
- **Terraform** installed (>= 1.0) - [Install Guide](https://developer.hashicorp.com/terraform/downloads)
- **Python 3.9+** installed locally
- **pip** package manager
- An **AWS account** with SES enabled in your region

> **Note**: This configuration is optimized for sandbox/development environments. All resources are tagged as "sandbox" and use appropriate naming conventions for testing.

### 1. Configure Variables

```bash
# Copy the example configuration
cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars

# Edit with your specific values
nano infrastructure/terraform.tfvars
```

**Key variables to update:**

```hcl
# Must be globally unique
email_bucket_name = "sandbox-ses-emails-yourname-12345"

# Your domain email that will trigger processing (use a test domain for sandbox)
email_recipient = "test@yourdomain.com"

# AWS region
aws_region = "us-east-1"
```

### 2. Deploy Infrastructure

```bash
# Run the deployment script
./scripts/deploy.sh

# Choose option 1: Initialize and deploy
```

The script will:

- ✅ Check all prerequisites
- ✅ Create Lambda deployment package
- ✅ Initialize Terraform
- ✅ Show you the deployment plan
- ✅ Deploy all AWS resources
- ✅ Configure S3 notifications

### 3. Configure SES Domain

```bash
# Verify your domain in SES
aws ses verify-domain-identity --domain yourdomain.com

# Check verification status
aws ses get-identity-verification-attributes --identities yourdomain.com
```

Add the DNS records provided by AWS to your domain's DNS settings.

### 4. Test the Setup

```bash
# Run comprehensive tests
./scripts/test.sh
# Choose option 6: Run all tests
```

## 🔧 Detailed Configuration

### Terraform Variables

Edit `infrastructure/terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "us-east-1"

# S3 Bucket (must be globally unique)
email_bucket_name = "sandbox-ses-emails-yourname-2024"

# Lambda Configuration
lambda_function_name = "ses-email-to-pdf-converter"
lambda_zip_path = "../lambda-deployment-package.zip"

# SES Configuration
ses_rule_name = "sandbox-email-to-pdf-rule"
email_recipient = "test@yourdomain.com"

# CloudWatch log retention (days)
log_retention_days = 14

# S3 configuration for sandbox environment
s3_force_destroy = true
email_retention_days = 30

# Resource Tags
tags = {
  Project     = "SES-Email-to-PDF"
  Environment = "sandbox"
  ManagedBy   = "Terraform"
  Owner       = "your-team"
}
```

### SES Receipt Rule

The Terraform configuration automatically creates:

- SES receipt rule set
- SES receipt rule that triggers on your specified email
- S3 action to store emails
- SNS notification for processing events

### Lambda Function

The Lambda function:

- Triggers when emails are stored in S3
- Converts emails to professionally formatted PDFs
- Stores PDFs back to S3 in the `emails/pdf/` folder
- Handles both HTML and plain text emails

### Directory Structure After Deployment

```
your-s3-bucket/
├── emails/                    # Original emails from SES
│   ├── email-001.txt
│   ├── email-002.txt
│   └── ...
└── emails/pdf/               # Generated PDFs
    ├── email-001.pdf
    ├── email-002.pdf
    └── ...
```

## 🛠️ Deployment Options

The deployment script (`./scripts/deploy.sh`) provides several options:

1. **Initialize and deploy** - First time setup
2. **Plan changes** - Preview infrastructure changes
3. **Apply changes** - Deploy infrastructure updates
4. **Update Lambda code only** - Quick code updates
5. **Destroy infrastructure** - Clean removal

## 🧪 Testing Options

The testing script (`./scripts/test.sh`) offers comprehensive testing:

1. **Syntax check** - Validates Python code without dependencies
2. **Mock test** - Tests with sample data locally
3. **S3 upload test** - End-to-end test with real AWS resources
4. **Lambda remote test** - Direct Lambda function invocation
5. **SES email test** - Send test email through SES
6. **Run all tests** - Complete test suite

## 📊 Generated PDF Features

The converted PDFs include:

- **Email metadata** (subject, sender, recipient, date)
- **Formatted content** with proper line breaks and spacing
- **Section headers** (ALL CAPS text becomes bold headers)
- **Bullet points** with proper indentation
- **HTML conversion** with preserved structure
- **Attachment information** (filename, type, size)
- **Professional styling** with colors and formatting

## 🏗️ Infrastructure

This project uses **Terraform** for infrastructure as code, providing:

- ✅ Better state management and drift detection
- ✅ More readable HCL syntax
- ✅ Extensive provider ecosystem
- ✅ Plan/apply workflow for safe deployments
- ✅ Module support for reusability
- ✅ **Idempotent design** - automatically handles existing resources

### Idempotent Resource Management

The infrastructure is designed to be fully idempotent:
- **Existing S3 buckets** are used without conflicts
- **Existing CloudWatch log groups** are preserved
- **Existing Lambda functions** can be updated or preserved
- **Lifecycle rules** prevent accidental resource destruction

See `infrastructure/README.md` for additional Terraform configuration details.

## 🔧 Configuration

### Environment Variables

Set in the Lambda function:
- `EMAIL_BUCKET`: S3 bucket name (auto-configured)
- `INCLUDE_FOOTER`: "true" or "false" to show/hide footer

### S3 Bucket Organization

```
your-ses-bucket/
├── emails/                    # Original emails from SES
│   ├── email-001.txt
│   └── email-002.txt
└── emails/pdf/               # Generated PDFs from Lambda
    ├── email-001.pdf
    └── email-002.pdf
```

## 💰 Cost Optimization

For typical usage (1000 emails/month):

- **Lambda**: ~$0.20
- **S3 Storage**: ~$0.50
- **SES**: ~$0.10
- **Total**: ~$0.80/month

To minimize costs:

- Use S3 lifecycle policies to archive old emails
- Set appropriate Lambda memory (512MB is usually sufficient)
- Monitor CloudWatch metrics for optimization opportunities

## 🔒 Security Best Practices

The solution implements:

- ✅ S3 bucket with public access blocked
- ✅ IAM roles with least-privilege access
- ✅ Email content encrypted at rest
- ✅ SES spam and virus scanning
- ✅ Account-restricted resource access

## 🔄 Updates and Maintenance

### Code Changes Only

```bash
./scripts/deploy.sh
# Choose option 4: Update Lambda code only
```

### Infrastructure Changes

```bash
# Edit terraform.tfvars or .tf files
./scripts/deploy.sh
# Choose option 2: Plan changes
# Then option 3: Apply changes
```

### Complete Redeployment

```bash
# Destroy everything
./scripts/cleanup.sh

# Redeploy
./scripts/deploy.sh
```

## 🆘 Getting Help

- **Terraform Issues**: Check [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- **AWS Issues**: Review CloudWatch logs and AWS documentation
- **Lambda Issues**: Test locally with sample data first
- **SES Issues**: Verify domain and check SES console

## 🧹 Cleanup

To remove all resources:

```bash
./scripts/cleanup.sh
```

Choose option 1 to delete everything including stored emails, or option 2 to keep the S3 bucket with your data.

## 📋 Troubleshooting

### Common Issues & Solutions

#### 1. Bucket Name Already Exists

```
Error: bucket already exists
```

**Solution**: Update `email_bucket_name` in `terraform.tfvars` with a unique name.

#### 2. SES Domain Not Verified

```
Error: domain not verified
```

**Solution**:

```bash
aws ses verify-domain-identity --domain yourdomain.com
# Add DNS records as instructed by AWS
```

#### 3. Permission Errors

```
Error: insufficient permissions
```

**Solution**: Ensure your AWS credentials have these permissions:

- IAM: Create/manage roles and policies
- Lambda: Create/manage functions
- S3: Create/manage buckets
- SES: Create/manage receipt rules
- SNS: Create/manage topics

#### 4. Resources Already Exist

```
Error: resource already exists
```

**Solution**: Terraform will automatically handle existing resources with lifecycle rules. If you still get errors, check the specific resource and consider using `terraform import` manually.

#### 5. S3 Bucket Not Empty

```
Error: bucket not empty
```

**Solution**: Either empty the bucket or enable force destroy:

```bash
# Option 1: Use cleanup script
./scripts/cleanup.sh
# Choose option 1: Empty bucket and destroy infrastructure

# Option 2: Enable force destroy in terraform.tfvars
s3_force_destroy = true
```

#### 6. Terraform State Issues

```
Error: state lock
```

**Solution**:

```bash
cd infrastructure
terraform force-unlock <lock-id>
```

### Monitoring & Debugging

#### CloudWatch Logs

```bash
# View Lambda logs (real-time)
aws logs tail /aws/lambda/ses-email-to-pdf-converter --follow

# View recent errors only
aws logs filter-log-events \
  --log-group-name /aws/lambda/ses-email-to-pdf-converter \
  --filter-pattern "ERROR"

# View logs from last hour
aws logs filter-log-events \
  --log-group-name /aws/lambda/ses-email-to-pdf-converter \
  --start-time $(date -d '1 hour ago' +%s)000

# View successful conversions
aws logs filter-log-events \
  --log-group-name /aws/lambda/ses-email-to-pdf-converter \
  --filter-pattern "Successfully converted email to PDF"
```

#### S3 Bucket Contents

```bash
# List emails
aws s3 ls s3://your-bucket-name/emails/ --recursive

# List generated PDFs
aws s3 ls s3://your-bucket-name/emails/pdf/ --recursive
```

#### Terraform State

```bash
cd infrastructure

# Show current infrastructure
terraform show

# List all resources
terraform state list

# Get specific resource details
terraform state show aws_lambda_function.email_to_pdf
```

#### Key Log Messages to Monitor

- `Processing email from bucket` - Email processing started
- `Successfully converted email to PDF` - Successful conversion
- `Error processing email` - Processing failures
- `Error downloading email from S3` - S3 access issues
- `Error uploading PDF to S3` - S3 upload failures

### Debug Commands

```bash
# Check Lambda logs (real-time)
aws logs tail /aws/lambda/ses-email-to-pdf-converter --follow

# Check recent Lambda logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/ses-email-to-pdf-converter \
  --start-time $(date -d '1 hour ago' +%s)000

# List S3 objects
aws s3 ls s3://your-bucket-name/emails/ --recursive

# Check Terraform state
terraform show
```

## 🔄 Updates and Maintenance

### Code Updates

For quick code changes:
```bash
./scripts/deploy.sh
# Choose option 4: Update Lambda code only
```

### Infrastructure Updates

For Terraform changes:
```bash
./scripts/deploy.sh
# Choose option 3: Apply changes
```

### Clean Redeploy

For major changes:
```bash
./scripts/deploy.sh
# Choose option 5: Destroy infrastructure, then option 1: Initialize and deploy
```

## 📚 Advanced Features

### Custom PDF Styling

Modify `src/lambda_function.py` to customize:
- Colors and fonts
- Page layout
- Header/footer content
- Section formatting

### Email Filtering

Add filtering logic to process only specific emails:
- Sender domain filtering
- Subject line filtering
- Content-based routing

### Notifications

Subscribe to the SNS topic for processing notifications:
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:region:account:ses-email-to-pdf-converter-notifications \
  --protocol email \
  --notification-endpoint your-email@domain.com
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is provided as-is for educational and commercial use.

## 🆘 Support

For issues or questions:
1. Check CloudWatch logs for error details
2. Verify SES domain and rule configuration
3. Ensure all AWS permissions are correctly set
4. Test with simple emails first

---

**Built with ❤️ for the AWS community**