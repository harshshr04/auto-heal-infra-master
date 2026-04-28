terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for remote state
  # Uncomment and configure for your environment
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "auto-heal-infra/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Auto-Heal-Infrastructure"
      ManagedBy   = "Terraform"
    }
  }
}

# Optional: Configure CloudWatch logging
provider "aws" {
  alias  = "logs"
  region = var.aws_region
}
