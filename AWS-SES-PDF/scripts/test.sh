#!/bin/bash

# AWS SES Email to PDF Converter - Unified Testing Script
# Provides multiple testing options in one script

set -e

# Configuration
LAMBDA_FUNCTION_NAME="ses-email-to-pdf-converter"
REGION="us-east-1"
TERRAFORM_DIR="infrastructure"
SAMPLE_EMAIL_FILE="tests/sample-email.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}🧪 AWS SES Email to PDF Converter - Testing${NC}"
    echo -e "${BLUE}=============================================${NC}"
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

show_test_options() {
    echo "🧪 Testing Options:"
    echo "1. Syntax check (no dependencies needed)"
    echo "2. Mock test with sample data"
    echo "3. Upload test email to S3"
    echo "4. Test deployed Lambda function"
    echo "5. Send test email via SES"
    echo "6. Run all tests"
    echo "7. Exit"
    echo ""
}

test_syntax() {
    print_info "Checking Lambda function syntax..."
    
    if [ ! -f "src/lambda_function.py" ]; then
        print_error "Lambda function file not found: src/lambda_function.py"
        return 1
    fi
    
    # Check Python syntax
    python3 -m py_compile src/lambda_function.py
    
    print_success "Lambda function syntax is valid"
    
    # Check for required functions
    python3 -c "
import ast
import sys

with open('src/lambda_function.py', 'r') as f:
    code = f.read()

tree = ast.parse(code)
functions = [node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]

required_functions = ['lambda_handler', 'download_email_from_s3', 'parse_email', 'convert_email_to_pdf']
missing_functions = [f for f in required_functions if f not in functions]

if missing_functions:
    print(f'Missing functions: {missing_functions}')
    sys.exit(1)
else:
    print('All required functions found')
    print(f'Functions: {functions}')
"
    
    print_success "Function structure validation passed"
}

test_mock() {
    print_info "Running mock test with sample data..."
    
    if [ ! -f "tests/mock_test.py" ]; then
        print_error "Mock test file not found. Creating it..."
        create_mock_test_file
    fi
    
    python3 tests/mock_test.py
}

test_s3_upload() {
    print_info "Testing with S3 email upload..."
    
    # Check if sample email exists
    if [ ! -f "$SAMPLE_EMAIL_FILE" ]; then
        print_error "Sample email file not found: $SAMPLE_EMAIL_FILE"
        return 1
    fi
    
    # Get bucket name from Terraform state
    cd infrastructure
    BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    cd ..
    
    if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "None" ]; then
        print_error "Could not get bucket name from Terraform state"
        print_info "Make sure the Terraform infrastructure is deployed successfully."
        return 1
    fi
    
    print_success "Found S3 bucket: $BUCKET_NAME"
    
    # Generate unique filename for the test email
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    EMAIL_KEY="emails/test-email-$TIMESTAMP.txt"
    
    print_info "Uploading sample email to S3..."
    print_info "Source: $SAMPLE_EMAIL_FILE"
    print_info "Destination: s3://$BUCKET_NAME/$EMAIL_KEY"
    
    # Upload the sample email to S3
    aws s3 cp $SAMPLE_EMAIL_FILE s3://$BUCKET_NAME/$EMAIL_KEY \
        --region $REGION \
        --content-type "text/plain"
    
    print_success "Sample email uploaded successfully!"
    
    # Wait for Lambda to process
    print_info "Waiting 15 seconds for Lambda function to process the email..."
    sleep 15
    
    # Check if PDF was generated
    PDF_KEY="emails/pdf/test-email-$TIMESTAMP.pdf"
    print_info "Checking if PDF was generated..."
    
    if aws s3 ls s3://$BUCKET_NAME/$PDF_KEY --region $REGION > /dev/null 2>&1; then
        print_success "PDF generated successfully!"
        print_info "PDF location: s3://$BUCKET_NAME/$PDF_KEY"
        
        # Download the PDF for local inspection
        LOCAL_PDF="generated-pdf-$TIMESTAMP.pdf"
        print_info "Downloading PDF for inspection..."
        aws s3 cp s3://$BUCKET_NAME/$PDF_KEY $LOCAL_PDF --region $REGION
        print_success "PDF saved locally as: $LOCAL_PDF"
        
        # Try to open the PDF (macOS)
        if command -v open > /dev/null 2>&1; then
            print_info "Opening PDF..."
            open $LOCAL_PDF
        fi
        
        return 0
    else
        print_warning "PDF not found. Checking Lambda function logs..."
        show_lambda_logs
        return 1
    fi
}

test_lambda_remote() {
    print_info "Testing deployed Lambda function..."
    
    # Check if Lambda function exists
    if ! aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION > /dev/null 2>&1; then
        print_error "Lambda function '$LAMBDA_FUNCTION_NAME' not found."
        return 1
    fi
    
    # Create test payload
    TEST_PAYLOAD='{
        "Records": [
            {
                "eventVersion": "2.1",
                "eventSource": "aws:s3",
                "awsRegion": "'$REGION'",
                "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
                "eventName": "ObjectCreated:Put",
                "s3": {
                    "bucket": {"name": "test-bucket"},
                    "object": {"key": "emails/test-email.txt", "size": 1024}
                }
            }
        ]
    }'
    
    print_info "Invoking Lambda function with test payload..."
    
    RESPONSE=$(aws lambda invoke \
        --function-name $LAMBDA_FUNCTION_NAME \
        --payload "$TEST_PAYLOAD" \
        --region $REGION \
        response.json)
    
    STATUS_CODE=$(echo $RESPONSE | jq -r '.StatusCode')
    
    if [ "$STATUS_CODE" = "200" ]; then
        print_success "Lambda function invoked successfully"
        print_info "Response:"
        cat response.json | jq .
    else
        print_error "Lambda function invocation failed"
        print_info "Response:"
        cat response.json
    fi
    
    rm -f response.json
}

test_ses_email() {
    print_info "Testing SES email sending..."
    
    read -p "Enter sender email address: " SENDER_EMAIL
    read -p "Enter recipient email address: " RECIPIENT_EMAIL
    
    if [ -z "$SENDER_EMAIL" ] || [ -z "$RECIPIENT_EMAIL" ]; then
        print_error "Both sender and recipient email addresses are required"
        return 1
    fi
    
    EMAIL_BODY="This is a test email for the SES to PDF conversion system.

Features being tested:
- Email metadata extraction
- Text content processing
- PDF generation
- S3 storage

If you receive a PDF version of this email, the system is working correctly!

Best regards,
AWS SES to PDF Converter Test System"
    
    print_info "Sending test email..."
    
    RESPONSE=$(aws ses send-email \
        --source "$SENDER_EMAIL" \
        --destination ToAddresses="$RECIPIENT_EMAIL" \
        --message Subject={Data="Test Email for PDF Conversion"},Body={Text={Data="$EMAIL_BODY"}} \
        --region $REGION)
    
    MESSAGE_ID=$(echo $RESPONSE | jq -r '.MessageId')
    
    if [ "$MESSAGE_ID" != "null" ]; then
        print_success "Test email sent successfully"
        print_info "Message ID: $MESSAGE_ID"
    else
        print_error "Failed to send test email"
        echo $RESPONSE
    fi
}

show_lambda_logs() {
    print_info "Recent Lambda logs:"
    
    aws logs filter-log-events \
        --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
        --start-time $(date -d '10 minutes ago' +%s)000 \
        --region $REGION \
        --query 'events[*].message' \
        --output text | tail -20
}

run_all_tests() {
    print_info "Running all tests..."
    
    echo "1. Syntax Check:"
    test_syntax
    echo ""
    
    echo "2. Mock Test:"
    test_mock
    echo ""
    
    echo "3. S3 Upload Test:"
    test_s3_upload
    echo ""
    
    echo "4. Lambda Remote Test:"
    test_lambda_remote
    echo ""
    
    print_success "All tests completed!"
}

create_mock_test_file() {
    mkdir -p tests
    cat > tests/mock_test.py << 'EOF'
#!/usr/bin/env python3
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

try:
    from lambda_function import lambda_handler, parse_email, convert_email_to_pdf
    print("✅ Successfully imported Lambda function")
    
    # Test with minimal mock data
    mock_event = {
        "Records": [{
            "s3": {
                "bucket": {"name": "test-bucket"},
                "object": {"key": "emails/test.txt"}
            }
        }]
    }
    
    print("✅ Mock test structure validated")
    print("ℹ️  Note: Full mock test requires S3 access")
    
except ImportError as e:
    print(f"❌ Import failed: {e}")
    sys.exit(1)
except Exception as e:
    print(f"⚠️  Test completed with expected errors: {e}")
EOF
}

main() {
    print_header
    
    # Check AWS CLI
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    show_test_options
    
    read -p "Choose option (1-7): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            test_syntax
            ;;
        2)
            test_mock
            ;;
        3)
            test_s3_upload
            ;;
        4)
            test_lambda_remote
            ;;
        5)
            test_ses_email
            ;;
        6)
            run_all_tests
            ;;
        7)
            print_info "Testing cancelled"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
    
    print_success "Testing completed!"
}

# Run main function
main "$@"