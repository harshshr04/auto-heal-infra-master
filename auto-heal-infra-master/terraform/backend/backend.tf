# Terraform Backend Configuration for Remote State Management
# 
# This configuration stores Terraform state in an S3 bucket with:
# - Encryption at rest
# - Versioning enabled
# - DynamoDB table for state locking
#
# To use this backend:
# 1. Create an S3 bucket and DynamoDB table manually or via separate Terraform
# 2. Update the bucket and region names below
# 3. Run: terraform init -backend-config="bucket=<your-bucket>" ...

terraform {
  backend "s3" {
    # ⚠️  UPDATE THESE VALUES BEFORE USING IN PRODUCTION
    
    # S3 bucket for storing terraform state
    # bucket = "your-terraform-state-bucket-name"
    
    # Key path within bucket
    key = "auto-heal-infra/terraform.tfstate"
    
    # AWS region where S3 bucket is located
    # region = "us-east-1"
    
    # Encrypt state file at rest
    encrypt = true
    
    # Enable versioning for state file
    # bucket_versioning = "Enabled"
    
    # DynamoDB table for state locking
    # Prevents concurrent modifications
    # dynamodb_table = "terraform-locks"
  }
}

# To initialize with backend configuration from command line:
# 
# terraform init \
#   -backend-config="bucket=your-bucket-name" \
#   -backend-config="key=auto-heal-infra/terraform.tfstate" \
#   -backend-config="region=us-east-1" \
#   -backend-config="encrypt=true" \
#   -backend-config="dynamodb_table=terraform-locks"
#
# Or use -backend-config with a file:
#
# Create backend-config.hcl with:
# bucket         = "your-bucket-name"
# key            = "auto-heal-infra/terraform.tfstate"
# region         = "us-east-1"
# encrypt        = true
# dynamodb_table = "terraform-locks"
#
# Then run:
# terraform init -backend-config=backend-config.hcl

# ============================================================================
# TO CREATE THE NECESSARY AWS RESOURCES FOR BACKEND:
# ============================================================================

# Uncomment and run this section ONCE to create the S3 bucket and DynamoDB table
# Then comment it back out and use remote backend above

# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "auto-heal-infra-terraform-state-${data.aws_caller_identity.current.account_id}"
#
#   tags = {
#     Name = "auto-heal-infra-terraform-state"
#   }
# }

# resource "aws_s3_bucket_versioning" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   versioning_configuration {
#     status = "Enabled"
#   }
# }

# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# resource "aws_s3_bucket_public_access_block" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

# resource "aws_dynamodb_table" "terraform_locks" {
#   name           = "auto-heal-infra-terraform-locks"
#   billing_mode   = "PAY_PER_REQUEST"
#   hash_key       = "LockID"
#
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
#
#   tags = {
#     Name = "auto-heal-infra-terraform-locks"
#   }
# }

# data "aws_caller_identity" "current" {}
