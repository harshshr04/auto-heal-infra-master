variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for naming resources"
  type        = string
  default     = "auto-heal-infra"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# EC2 Configuration - Target Instances
variable "instance_type" {
  description = "EC2 instance type for target instances"
  type        = string
  default     = "t3.medium"
}

variable "target_instance_count" {
  description = "Number of target EC2 instances to create"
  type        = number
  default     = 2

  validation {
    condition     = var.target_instance_count > 0 && var.target_instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 20 and 100 GB."
  }
}

variable "root_volume_type" {
  description = "EBS volume type for root volume"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "Volume type must be gp2, gp3, io1, or io2."
  }
}

# Monitoring EC2 Configuration
variable "monitoring_instance_type" {
  description = "EC2 instance type for Nagios and Grafana"
  type        = string
  default     = "t3.medium"
}

variable "monitoring_volume_size" {
  description = "Size of monitoring EC2 root volume in GB"
  type        = number
  default     = 50
}

# AMI Configuration
variable "ami_name_filter" {
  description = "Filter for AMI name (e.g., amzn2-ami-hvm-*-x86_64-gp2)"
  type        = string
  default     = "amzn2-ami-hvm-*-x86_64-gp3"
}

variable "ami_owner" {
  description = "AMI owner (amazon, self, etc.)"
  type        = string
  default     = "amazon"
}

# CloudWatch Alarm Thresholds
variable "alarm_threshold_cpu" {
  description = "CPU utilization threshold (%) for alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.alarm_threshold_cpu > 0 && var.alarm_threshold_cpu < 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "alarm_threshold_memory" {
  description = "Memory utilization threshold (%) for alarm"
  type        = number
  default     = 85

  validation {
    condition     = var.alarm_threshold_memory > 0 && var.alarm_threshold_memory < 100
    error_message = "Memory threshold must be between 0 and 100."
  }
}

variable "alarm_threshold_disk" {
  description = "Disk utilization threshold (%) for alarm"
  type        = number
  default     = 90

  validation {
    condition     = var.alarm_threshold_disk > 0 && var.alarm_threshold_disk < 100
    error_message = "Disk threshold must be between 0 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for alarms"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period_seconds" {
  description = "Period for alarm evaluation in seconds"
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.alarm_period_seconds)
    error_message = "Period must be 60, 300, 900, or 3600 seconds."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 10 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 10 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256

  validation {
    condition     = contains([128, 256, 512, 1024, 2048], var.lambda_memory_size)
    error_message = "Lambda memory must be 128, 256, 512, 1024, or 2048 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention for Lambda in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.lambda_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch value."
  }
}

# SNS Configuration
variable "sns_topic_name" {
  description = "SNS topic name for alerts"
  type        = string
  default     = "auto-heal-alerts"
}

variable "enable_sns_fifo" {
  description = "Enable SNS FIFO topic for ordered delivery"
  type        = bool
  default     = false
}

# Nagios Configuration
variable "nagios_password" {
  description = "Initial Nagios admin password (CHANGE IN PRODUCTION!)"
  type        = string
  default     = "nagios"
  sensitive   = true

  validation {
    condition     = length(var.nagios_password) >= 6
    error_message = "Nagios password must be at least 6 characters."
  }
}

variable "nagios_contact_email" {
  description = "Email address for Nagios alerts"
  type        = string
  default     = "admin@example.com"
}

# Grafana Configuration
variable "grafana_admin_password" {
  description = "Initial Grafana admin password (CHANGE IN PRODUCTION!)"
  type        = string
  default     = "admin"
  sensitive   = true

  validation {
    condition     = length(var.grafana_admin_password) >= 6
    error_message = "Grafana admin password must be at least 6 characters."
  }
}

# Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Owner       = "DevOps Team"
    CostCenter  = "Infrastructure"
    Compliance  = "Auto-Heal"
  }
}

# Enable Features
variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring on EC2 instances"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable CloudWatch Logs for Lambda and instances"
  type        = bool
  default     = true
}

# Multi-region scanning (optional)
variable "enable_multi_region" {
  description = "Enable multi-region instance scanning in Lambda"
  type        = bool
  default     = false
}

variable "additional_regions" {
  description = "Additional AWS regions for multi-region scanning"
  type        = list(string)
  default     = ["us-west-2", "eu-west-1"]
}

# Key Pair Configuration
variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
  default     = "auto-heal-key"
}

# Healing Action Configuration
variable "auto_healing_enabled" {
  description = "Enable automatic healing actions"
  type        = bool
  default     = true
}

variable "healing_action_timeout" {
  description = "Timeout for healing actions in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.healing_action_timeout >= 60 && var.healing_action_timeout <= 3600
    error_message = "Healing timeout must be between 60 and 3600 seconds."
  }
}

variable "max_healing_attempts" {
  description = "Maximum number of healing attempts per instance"
  type        = number
  default     = 3

  validation {
    condition     = var.max_healing_attempts >= 1 && var.max_healing_attempts <= 10
    error_message = "Max healing attempts must be between 1 and 10."
  }
}
