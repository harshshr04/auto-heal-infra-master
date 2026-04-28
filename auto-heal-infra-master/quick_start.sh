#!/bin/bash

################################################################################
# Quick Start Script for Auto-Heal Infrastructure
#
# This script automates the initial setup and deployment of the
# Auto-Heal Infrastructure project on AWS.
#
# Usage: ./quick_start.sh [action]
#
# Actions:
#   - setup        Install prerequisites
#   - init         Initialize Terraform
#   - plan         Plan deployment
#   - deploy       Deploy infrastructure
#   - status       Show deployment status
#   - destroy      Destroy all resources
#   - help         Show this help message
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -o pipefail

# Configuration
PROJECT_NAME="auto-heal-infra"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
LAMBDA_DIR="$PROJECT_ROOT/lambda"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# UTILITY FUNCTIONS
################################################################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed"
        return 1
    fi
    print_success "$1 is installed"
    return 0
}

################################################################################
# SETUP FUNCTIONS
################################################################################

setup_prerequisites() {
    print_header "Checking Prerequisites"
    
    local all_installed=true
    
    # Check required commands
    check_command "terraform" || all_installed=false
    check_command "aws" || all_installed=false
    check_command "git" || all_installed=false
    check_command "jq" || all_installed=false
    
    if [ "$all_installed" = false ]; then
        print_error "Some prerequisites are missing!"
        echo ""
        echo "Installation instructions:"
        echo "  Terraform: https://www.terraform.io/downloads.html"
        echo "  AWS CLI: https://aws.amazon.com/cli/"
        echo "  Git: https://git-scm.com/"
        echo "  jq: https://stedolan.github.io/jq/download/"
        return 1
    fi
    
    print_success "All prerequisites are installed!"
    
    # Check AWS credentials
    print_info "Checking AWS credentials..."
    if aws sts get-caller-identity &>/dev/null; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --query Arn --output text)
        print_success "AWS credentials configured"
        echo "  Account ID: $account_id"
        echo "  User/Role: $user_arn"
    else
        print_error "AWS credentials not configured"
        return 1
    fi
    
    # Check Terraform version
    print_info "Checking Terraform version..."
    local tf_version=$(terraform version | grep Terraform | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -z "$tf_version" ]; then
        print_error "Could not determine Terraform version"
        return 1
    fi
    print_success "Terraform v$tf_version installed"
    
    # Check project structure
    print_info "Checking project structure..."
    if [ ! -f "$TERRAFORM_DIR/main.tf" ]; then
        print_error "Terraform files not found in $TERRAFORM_DIR"
        return 1
    fi
    print_success "Project structure verified"
    
    return 0
}

check_terraform_files() {
    print_header "Verifying Terraform Files"
    
    local required_files=(
        "main.tf"
        "variables.tf"
        "outputs.tf"
        "providers.tf"
        "monitoring_sg.tf"
        "nagios_ec2.tf"
        "grafana_ec2.tf"
    )
    
    local all_exist=true
    for file in "${required_files[@]}"; do
        if [ -f "$TERRAFORM_DIR/$file" ]; then
            print_success "$file exists"
        else
            print_error "$file missing"
            all_exist=false
        fi
    done
    
    # Check tfvars file
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        print_success "terraform.tfvars found"
    else
        print_warning "terraform.tfvars not found (copy from terraform.tfvars.example)"
        if [ -f "$TERRAFORM_DIR/terraform.tfvars.example" ]; then
            cp "$TERRAFORM_DIR/terraform.tfvars.example" "$TERRAFORM_DIR/terraform.tfvars"
            print_success "Created terraform.tfvars from template"
        fi
    fi
    
    return $([ "$all_exist" = true ] && echo 0 || echo 1)
}

initialize_terraform() {
    print_header "Initializing Terraform"
    
    cd "$TERRAFORM_DIR"
    
    # Check for existing state
    if [ -f "terraform.tfstate" ]; then
        print_warning "Existing terraform.tfstate found"
    fi
    
    print_info "Running terraform init..."
    if terraform init; then
        print_success "Terraform initialized"
        return 0
    else
        print_error "Terraform initialization failed"
        return 1
    fi
}

validate_terraform() {
    print_header "Validating Terraform Configuration"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Running terraform validate..."
    if terraform validate; then
        print_success "Terraform configuration is valid"
        return 0
    else
        print_error "Terraform validation failed"
        return 1
    fi
}

format_terraform() {
    print_header "Formatting Terraform Code"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Running terraform fmt..."
    terraform fmt -recursive
    print_success "Terraform code formatted"
}

plan_deployment() {
    print_header "Planning Terraform Deployment"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Running terraform plan..."
    if terraform plan -out=tfplan; then
        print_success "Plan saved to tfplan"
        
        # Show resource count
        local resource_count=$(terraform plan -out=tfplan 2>&1 | grep -c "+" || true)
        print_info "Resources to be created: ~$resource_count"
        
        return 0
    else
        print_error "Terraform plan failed"
        return 1
    fi
}

deploy_infrastructure() {
    print_header "Deploying Infrastructure"
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "tfplan" ]; then
        print_warning "tfplan not found, running plan first..."
        if ! terraform plan -out=tfplan; then
            print_error "Terraform plan failed"
            return 1
        fi
    fi
    
    print_info "Running terraform apply..."
    if terraform apply tfplan; then
        print_success "Infrastructure deployed successfully!"
        return 0
    else
        print_error "Terraform apply failed"
        return 1
    fi
}

show_deployment_status() {
    print_header "Deployment Status"
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfstate" ]; then
        print_warning "No deployment found (terraform.tfstate not found)"
        return 1
    fi
    
    print_info "Terraform State Summary:"
    terraform state list | head -20
    
    print_info "\nKey Outputs:"
    terraform output -json 2>/dev/null | jq -r 'to_entries[] | "\(.key): \(.value.value)"' | head -10
    
    print_info "\nAWS Resources:"
    
    # EC2 instances
    print_info "EC2 Instances:"
    aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=$PROJECT_NAME" \
        --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,State.Name,InstanceType]' \
        --output table 2>/dev/null || print_warning "Could not fetch EC2 instances"
    
    # Lambda function
    print_info "Lambda Functions:"
    aws lambda list-functions \
        --query "Functions[?contains(FunctionName, '$PROJECT_NAME')].{Name:FunctionName,Runtime:Runtime,Status:State}" \
        --output table 2>/dev/null || print_warning "Could not fetch Lambda functions"
    
    # SNS topics
    print_info "SNS Topics:"
    aws sns list-topics \
        --query "Topics[?contains(TopicArn, '$PROJECT_NAME')].TopicArn" \
        --output table 2>/dev/null || print_warning "Could not fetch SNS topics"
}

destroy_infrastructure() {
    print_header "Destroying Infrastructure"
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfstate" ]; then
        print_warning "No deployment found (terraform.tfstate not found)"
        return 1
    fi
    
    print_warning "This will destroy all resources created by Terraform!"
    echo ""
    read -p "Type 'yes' to confirm destruction: " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Destruction cancelled"
        return 0
    fi
    
    print_info "Running terraform destroy..."
    if terraform destroy -auto-approve; then
        print_success "Infrastructure destroyed successfully"
        return 0
    else
        print_error "Terraform destroy failed"
        return 1
    fi
}

show_outputs() {
    print_header "Deployment Outputs"
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfstate" ]; then
        print_error "No deployment found"
        return 1
    fi
    
    print_info "Running terraform output..."
    terraform output
    
    # Extract key URLs
    echo ""
    print_info "Quick Access URLs:"
    
    local nagios_ip=$(terraform output -raw nagios_public_ip 2>/dev/null)
    if [ -n "$nagios_ip" ]; then
        echo "  Nagios: http://$nagios_ip/nagios (user: nagiosadmin, pass: nagios)"
    fi
    
    local grafana_ip=$(terraform output -raw grafana_public_ip 2>/dev/null)
    if [ -n "$grafana_ip" ]; then
        echo "  Grafana: http://$grafana_ip:3000 (user: admin, pass: admin)"
    fi
}

show_help() {
    cat << EOF
${BLUE}Auto-Heal Infrastructure Quick Start${NC}

Usage: $0 [action]

Actions:
  ${GREEN}setup${NC}       Check and install prerequisites
  ${GREEN}init${NC}        Initialize Terraform
  ${GREEN}validate${NC}    Validate Terraform configuration
  ${GREEN}format${NC}      Format Terraform code
  ${GREEN}plan${NC}        Plan infrastructure deployment
  ${GREEN}deploy${NC}      Deploy infrastructure
  ${GREEN}status${NC}      Show deployment status
  ${GREEN}outputs${NC}     Show deployment outputs and URLs
  ${GREEN}destroy${NC}     Destroy all resources
  ${GREEN}help${NC}        Show this help message

Examples:
  # Initial setup
  $0 setup
  $0 init
  $0 validate
  $0 plan

  # Deploy
  $0 deploy

  # Check status
  $0 status
  $0 outputs

  # Cleanup
  $0 destroy

Full Documentation: DEPLOYMENT_GUIDE.md

EOF
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local action="${1:-help}"
    
    case "$action" in
        setup)
            setup_prerequisites
            ;;
        init)
            check_terraform_files && initialize_terraform && validate_terraform
            ;;
        validate)
            cd "$TERRAFORM_DIR"
            terraform validate
            ;;
        format)
            format_terraform
            ;;
        plan)
            initialize_terraform && validate_terraform && plan_deployment
            ;;
        deploy)
            deploy_infrastructure && show_outputs
            ;;
        status)
            show_deployment_status
            ;;
        outputs)
            show_outputs
            ;;
        destroy)
            destroy_infrastructure
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown action: $action"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main
main "$@"
