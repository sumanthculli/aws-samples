#!/bin/bash

# AWS SES Email to PDF Converter - Cleanup Script
# Safely removes all Terraform resources with data preservation options

set -e

# Configuration
TERRAFORM_DIR="infrastructure"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}🧹 AWS SES Email to PDF Converter - Cleanup${NC}"
    echo -e "${BLUE}============================================${NC}"
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

main() {
    print_header
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform > /dev/null 2>&1; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check if Terraform state exists
    if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ] || [ ! -s "$TERRAFORM_DIR/terraform.tfstate" ]; then
        print_info "No Terraform state found. Nothing to clean up."
        exit 0
    fi
    
    # Get bucket name from Terraform state
    print_info "Getting infrastructure information..."
    cd $TERRAFORM_DIR
    BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    cd ..
    
    if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "None" ]; then
        print_success "Found S3 bucket: $BUCKET_NAME"
        
        # Check if bucket has objects
        OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket $BUCKET_NAME --query 'KeyCount' --output text 2>/dev/null || echo "0")
        VERSION_COUNT=$(aws s3api list-object-versions --bucket $BUCKET_NAME --query 'length(Versions)' --output text 2>/dev/null || echo "0")
        
        echo ""
        print_info "Bucket contents:"
        echo "  - Objects: $OBJECT_COUNT"
        echo "  - Versions: $VERSION_COUNT"
        
        if [ "$OBJECT_COUNT" -gt 0 ] || [ "$VERSION_COUNT" -gt 0 ]; then
            echo ""
            print_warning "Bucket contains objects/versions. Options:"
            echo "1. Empty bucket and destroy infrastructure (DESTRUCTIVE - will lose all emails/PDFs)"
            echo "2. Destroy infrastructure only (bucket will be retained with data)"
            echo "3. Cancel cleanup"
            echo ""
            read -p "Choose option (1/2/3): " -n 1 -r
            echo ""
            
            case $REPLY in
                1)
                    print_warning "This will permanently delete all emails and PDFs!"
                    read -p "Type 'DELETE' to confirm: " -r
                    if [ "$REPLY" = "DELETE" ]; then
                        print_info "Emptying bucket..."
                        
                        # Delete all current objects
                        aws s3 rm s3://$BUCKET_NAME --recursive --region $REGION 2>/dev/null || true
                        
                        # Delete all object versions and delete markers
                        aws s3api list-object-versions --bucket $BUCKET_NAME --region $REGION --output json 2>/dev/null | \
                        jq -r '.Versions[]?, .DeleteMarkers[]? | "--key \"\(.Key)\" --version-id \(.VersionId)"' | \
                        while read -r line; do
                            if [ -n "$line" ]; then
                                eval "aws s3api delete-object --bucket $BUCKET_NAME --region $REGION $line" 2>/dev/null || true
                            fi
                        done
                        
                        print_success "Bucket emptied"
                        
                        print_info "Destroying Terraform infrastructure..."
                        cd $TERRAFORM_DIR
                        terraform destroy -auto-approve
                        cd ..
                        print_success "Infrastructure destroyed"
                    else
                        print_info "Cleanup cancelled"
                        exit 0
                    fi
                    ;;
                2)
                    print_info "Destroying Terraform infrastructure (bucket will be retained)..."
                    cd $TERRAFORM_DIR
                    terraform destroy -auto-approve
                    cd ..
                    print_success "Infrastructure destroyed"
                    print_info "Bucket $BUCKET_NAME will be retained with your data"
                    ;;
                3)
                    print_info "Cleanup cancelled"
                    exit 0
                    ;;
                *)
                    print_error "Invalid option. Cleanup cancelled"
                    exit 1
                    ;;
            esac
        else
            print_info "Bucket is empty. Destroying infrastructure..."
            cd $TERRAFORM_DIR
            terraform destroy -auto-approve
            cd ..
            print_success "Infrastructure destroyed"
        fi
    else
        print_info "No S3 bucket found. Destroying infrastructure..."
        cd $TERRAFORM_DIR
        terraform destroy -auto-approve
        cd ..
        print_success "Infrastructure destroyed"
    fi
    
    echo ""
    print_info "You can check the current state with:"
    echo "cd $TERRAFORM_DIR && terraform show"
    echo ""
    print_success "Cleanup script completed!"
}

# Run main function
main "$@"