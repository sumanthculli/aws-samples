#!/bin/bash

# AWS SES Email to PDF Converter - Deployment Script
# Handles Terraform deployment with interactive options

set -e

# Configuration
LAMBDA_FUNCTION_NAME="ses-email-to-pdf-converter"
REGION="us-east-1"
PACKAGE_FILE="lambda-deployment-package.zip"
TERRAFORM_DIR="infrastructure"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}🚀 AWS SES Email to PDF Converter${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform > /dev/null 2>&1; then
        print_error "Terraform is not installed. Please install Terraform first."
        echo "Visit: https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi
    
    # Check AWS CLI
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Python and pip
    if ! command -v python3 > /dev/null 2>&1; then
        print_error "Python 3 is required but not installed."
        exit 1
    fi
    
    if ! command -v pip > /dev/null 2>&1; then
        print_error "pip is required but not installed."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

show_deployment_options() {
    echo ""
    echo "🔧 Deployment Options:"
    echo "1. Initialize and deploy (first time)"
    echo "2. Plan changes"
    echo "3. Apply changes"
    echo "4. Update Lambda code only"
    echo "5. Destroy infrastructure"
    echo "6. Exit"
    echo ""
}

create_deployment_package() {
    print_info "Creating Lambda deployment package..."
    
    # Clean up any existing package
    rm -f $PACKAGE_FILE
    
    # Create temporary directory for package
    TEMP_DIR=$(mktemp -d)
    
    # Copy Lambda function
    cp src/lambda_function.py $TEMP_DIR/
    
    # Install dependencies
    print_info "Installing Python dependencies..."
    pip install -r src/requirements.txt -t $TEMP_DIR/ --upgrade --quiet
    
    # Create zip package
    cd $TEMP_DIR
    zip -r "$OLDPWD/$PACKAGE_FILE" . > /dev/null
    cd "$OLDPWD"
    rm -rf $TEMP_DIR
    
    # Verify package was created
    if [ ! -f "$PACKAGE_FILE" ]; then
        print_error "Failed to create deployment package"
        exit 1
    fi
    
    print_success "Deployment package created: $PACKAGE_FILE"
}

check_terraform_vars() {
    if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found. Creating from example..."
        
        if [ -f "$TERRAFORM_DIR/terraform.tfvars.example" ]; then
            cp "$TERRAFORM_DIR/terraform.tfvars.example" "$TERRAFORM_DIR/terraform.tfvars"
            print_info "Please edit $TERRAFORM_DIR/terraform.tfvars with your specific values"
            print_info "Especially update:"
            echo "  - email_bucket_name (must be globally unique)"
            echo "  - email_recipient (your domain email)"
            echo ""
            read -p "Press Enter after updating terraform.tfvars..."
        else
            print_error "terraform.tfvars.example not found"
            exit 1
        fi
    fi
}

terraform_init() {
    print_info "Initializing Terraform..."
    cd $TERRAFORM_DIR
    terraform init
    cd ..
    print_success "Terraform initialized"
}

terraform_plan() {
    print_info "Planning Terraform changes..."
    cd $TERRAFORM_DIR
    terraform plan
    cd ..
    print_success "Terraform plan completed"
}

terraform_apply() {
    print_info "Applying Terraform changes..."
    cd $TERRAFORM_DIR
    
    # Apply Terraform changes
    terraform apply
    
    cd ..
    print_success "Terraform apply completed"
}

terraform_destroy() {
    print_warning "This will destroy all infrastructure!"
    read -p "Type 'DESTROY' to confirm: " -r
    
    if [ "$REPLY" != "DESTROY" ]; then
        print_info "Destroy cancelled"
        return 1
    fi
    
    print_info "Destroying Terraform infrastructure..."
    cd $TERRAFORM_DIR
    terraform destroy
    cd ..
    print_success "Infrastructure destroyed"
}

init_and_deploy() {
    check_terraform_vars
    create_deployment_package
    terraform_init
    terraform_plan
    
    echo ""
    read -p "Apply these changes? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform_apply
        show_deployment_summary
    else
        print_info "Deployment cancelled"
    fi
}

update_lambda_code_only() {
    print_info "Updating Lambda function code only..."
    
    # Get function name from Terraform output
    cd $TERRAFORM_DIR
    FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo $LAMBDA_FUNCTION_NAME)
    cd ..
    
    # Check if Lambda function exists
    if ! aws lambda get-function --function-name $FUNCTION_NAME --region $REGION > /dev/null 2>&1; then
        print_error "Lambda function '$FUNCTION_NAME' not found."
        print_info "You need to deploy the infrastructure first."
        return 1
    fi
    
    create_deployment_package
    
    # Update Lambda function code
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://$PACKAGE_FILE \
        --region $REGION > /dev/null
    
    print_success "Lambda function code updated successfully"
}

show_deployment_summary() {
    print_info "Getting deployment information..."
    
    cd $TERRAFORM_DIR
    
    BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "Unknown")
    LAMBDA_ARN=$(terraform output -raw lambda_function_arn 2>/dev/null || echo "Unknown")
    LAMBDA_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo "Unknown")
    SNS_TOPIC=$(terraform output -raw sns_topic_arn 2>/dev/null || echo "Unknown")
    
    cd ..
    
    echo ""
    print_success "Deployment completed successfully!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  Lambda Function: $LAMBDA_NAME"
    echo "  Lambda ARN: $LAMBDA_ARN"
    echo "  S3 Bucket: $BUCKET_NAME"
    echo "  SNS Topic: $SNS_TOPIC"
    echo "  Region: $REGION"
    echo ""
    echo "📧 Next Steps:"
    echo "1. Configure your domain in SES and verify it"
    echo "2. Update the email_recipient in terraform.tfvars with your actual domain"
    echo "3. Test by running: ./scripts/test.sh"
    echo ""
}

cleanup_temp_files() {
    rm -f $PACKAGE_FILE
}

main() {
    print_header
    check_prerequisites
    
    # Check if Terraform state exists
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ] && [ -s "$TERRAFORM_DIR/terraform.tfstate" ]; then
        print_info "Existing Terraform state found."
        show_deployment_options
        
        read -p "Choose option (1-6): " -n 1 -r
        echo ""
        
        case $REPLY in
            1)
                print_error "Infrastructure already exists. Use option 3 to apply changes."
                exit 1
                ;;
            2)
                check_terraform_vars
                terraform_plan
                ;;
            3)
                check_terraform_vars
                create_deployment_package
                terraform_apply
                show_deployment_summary
                ;;
            4)
                update_lambda_code_only
                ;;
            5)
                terraform_destroy
                ;;
            6)
                print_info "Deployment cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
    else
        # First time deployment
        init_and_deploy
    fi
    
    # Verify S3 to Lambda trigger
    echo ""
    print_info "Verifying S3 to Lambda trigger configuration..."
    cd $TERRAFORM_DIR
    BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    cd ..
    
    if [ -n "$BUCKET_NAME" ]; then
        # Get the notification configuration with retry logic
        print_info "Checking S3 bucket notification configuration..."
        sleep 2  # Give AWS a moment to propagate the configuration
        
        NOTIFICATION_CONFIG=$(aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" 2>/dev/null || echo "{}")
        
        # Check multiple possible indicators of Lambda configuration
        if echo "$NOTIFICATION_CONFIG" | grep -q "LambdaFunctionArn" || \
           echo "$NOTIFICATION_CONFIG" | grep -q "lambda" || \
           echo "$NOTIFICATION_CONFIG" | grep -q "Lambda"; then
            print_success "✅ S3 to Lambda trigger is configured correctly"
            print_info "Upload a file to s3://$BUCKET_NAME/emails/ to test the trigger"
        else
            # Check if the configuration is just empty (which might be normal during deployment)
            if [ "$NOTIFICATION_CONFIG" = "{}" ] || [ -z "$NOTIFICATION_CONFIG" ]; then
                print_warning "⚠️  S3 bucket notification configuration is empty"
                print_info "This might be normal if resources are still being created"
                print_info "You can verify manually with: aws s3api get-bucket-notification-configuration --bucket $BUCKET_NAME"
            else
                print_warning "⚠️  S3 bucket notification may not be configured properly"
                print_info "Notification config: $NOTIFICATION_CONFIG"
            fi
            print_info "Try running 'terraform apply' again if the trigger doesn't work"
        fi
    fi
    
    cleanup_temp_files
    print_success "Deployment script completed!"
}

# Run main function
main "$@"