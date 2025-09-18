#!/bin/bash

# Create a source package with only files that should be version controlled
# Excludes files listed in .gitignore

set -e

# Configuration
PACKAGE_NAME="ses-email-to-pdf-source-$(date +%Y%m%d-%H%M%S).zip"
TEMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}📦 Creating Source Package${NC}"
    echo -e "${BLUE}==========================${NC}"
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
    
    print_info "Creating source package: $PACKAGE_NAME"
    print_info "Temporary directory: $TEMP_DIR"
    echo ""
    
    # Create project directory in temp
    PROJECT_DIR="$TEMP_DIR/AWS-SES-PDF"
    mkdir -p "$PROJECT_DIR"
    
    # Copy essential files and directories
    print_info "Copying source files..."
    
    # Root files
    cp README.md "$PROJECT_DIR/" 2>/dev/null || print_warning "README.md not found"
    cp .gitignore "$PROJECT_DIR/" 2>/dev/null || print_warning ".gitignore not found"
    
    # Source code
    if [ -d "src" ]; then
        cp -r src "$PROJECT_DIR/"
        print_success "Copied src/ directory"
    else
        print_warning "src/ directory not found"
    fi
    
    # Infrastructure code
    if [ -d "infrastructure" ]; then
        mkdir -p "$PROJECT_DIR/infrastructure"
        cp infrastructure/*.tf "$PROJECT_DIR/infrastructure/" 2>/dev/null || print_warning "No .tf files found"
        cp infrastructure/*.example "$PROJECT_DIR/infrastructure/" 2>/dev/null || print_warning "No .example files found"
        cp infrastructure/README.md "$PROJECT_DIR/infrastructure/" 2>/dev/null || print_warning "infrastructure/README.md not found"
        print_success "Copied infrastructure/ files"
    else
        print_warning "infrastructure/ directory not found"
    fi
    
    # Scripts
    if [ -d "scripts" ]; then
        mkdir -p "$PROJECT_DIR/scripts"
        cp scripts/*.sh "$PROJECT_DIR/scripts/" 2>/dev/null || print_warning "No shell scripts found"
        chmod +x "$PROJECT_DIR/scripts/"*.sh 2>/dev/null || true
        print_success "Copied scripts/ directory"
    else
        print_warning "scripts/ directory not found"
    fi
    
    # Tests directory (if exists)
    if [ -d "tests" ]; then
        cp -r tests "$PROJECT_DIR/"
        print_success "Copied tests/ directory"
    fi
    
    # Remove any files that shouldn't be included
    print_info "Cleaning up excluded files..."
    
    # Remove terraform state and variable files
    find "$PROJECT_DIR" -name "*.tfstate*" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name "*.tfvars" ! -name "*.tfvars.example" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_DIR" -name "terraform.tfplan*" -delete 2>/dev/null || true
    
    # Remove Python cache and build files
    find "$PROJECT_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_DIR" -name "*.pyc" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name "*.zip" -delete 2>/dev/null || true
    
    # Remove IDE and system files
    find "$PROJECT_DIR" -name ".DS_Store" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name "Thumbs.db" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name ".vscode" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_DIR" -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove log and temporary files
    find "$PROJECT_DIR" -name "*.log" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name "*.tmp" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name "test-*.txt" -delete 2>/dev/null || true
    find "$PROJECT_DIR" -name "test-*.pdf" -delete 2>/dev/null || true
    
    print_success "Cleanup completed"
    
    # Create the zip file
    print_info "Creating zip package..."
    cd "$TEMP_DIR"
    zip -r "$OLDPWD/$PACKAGE_NAME" AWS-SES-PDF/ > /dev/null
    cd "$OLDPWD"
    
    # Cleanup temp directory
    rm -rf "$TEMP_DIR"
    
    # Show package contents
    echo ""
    print_success "Source package created: $PACKAGE_NAME"
    print_info "Package contents:"
    unzip -l "$PACKAGE_NAME" | head -20
    
    if [ $(unzip -l "$PACKAGE_NAME" | wc -l) -gt 25 ]; then
        echo "... (showing first 20 files)"
        echo ""
        print_info "Total files: $(unzip -l "$PACKAGE_NAME" | tail -1 | awk '{print $2}')"
    fi
    
    echo ""
    print_info "Package size: $(ls -lh "$PACKAGE_NAME" | awk '{print $5}')"
    
    echo ""
    print_success "✨ Ready to send to your team member!"
    echo ""
    echo "📧 Instructions for your team member:"
    echo "1. Extract the zip file: unzip $PACKAGE_NAME"
    echo "2. Navigate to the directory: cd AWS-SES-PDF"
    echo "3. Review the changes and commit to version control"
    echo "4. Make sure to copy infrastructure/terraform.tfvars.example to terraform.tfvars and configure it"
}

# Run main function
main "$@"