# Data source for Amazon Linux 2 AMI - fallback to specific recent AMI ID
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Data source for EC2 assume role policy
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# ============================================================================
# VPC AND NETWORKING
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

# Public Subnets (for Nagios, Grafana, NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-subnet-${count.index + 1}"
    }
  )
}

# Private Subnets (for target instances)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-subnet-${count.index + 1}"
    }
  )
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat-eip"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-rt"
    }
  )
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ============================================================================
# TARGET EC2 INSTANCES
# ============================================================================

# IAM Role for Target Instances
resource "aws_iam_role" "target_instance_role" {
  name               = "${var.project_name}-target-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-target-role"
    }
  )
}

# IAM Policy for Target Instances (SSM + CloudWatch)
resource "aws_iam_role_policy" "target_instance_policy" {
  name   = "${var.project_name}-target-policy"
  role   = aws_iam_role.target_instance_role.id
  policy = data.aws_iam_policy_document.target_instance_policy.json
}

# Attach SSM Managed Instance Core policy
resource "aws_iam_role_policy_attachment" "target_ssm_policy" {
  role       = aws_iam_role.target_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch Agent Server Policy
resource "aws_iam_role_policy_attachment" "target_cloudwatch_policy" {
  role       = aws_iam_role.target_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile for Target Instances
resource "aws_iam_instance_profile" "target_instance_profile" {
  name = "${var.project_name}-target-profile"
  role = aws_iam_role.target_instance_role.name
}

# Data source: IAM policy document for target instances
data "aws_iam_policy_document" "target_instance_policy" {
  statement {
    sid    = "AllowSSMAccess"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListAssociations"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Target EC2 Instances
resource "aws_instance" "target" {
  count                = var.target_instance_count
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.private[count.index % 2].id
  iam_instance_profile = aws_iam_instance_profile.target_instance_profile.name

  vpc_security_group_ids = [aws_security_group.target_instances.id]

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-target-${count.index + 1}-root"
    }
  }

  # User data script to setup CloudWatch agent and application
  user_data = base64encode(<<EOF
#!/bin/bash
set -e

# CloudWatch agent configuration
CLOUDWATCH_NAMESPACE="${var.project_name}"
AWS_REGION="${var.aws_region}"
INSTANCE_NUMBER="${count.index + 1}"

# Log output
LOG_FILE="/var/log/auto-heal/user_data.log"
mkdir -p /var/log/auto-heal

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

log "Target Instance Setup Started"
log "Instance Number: $INSTANCE_NUMBER"
log "Region: $AWS_REGION"

# Update system
log "Updating system packages..."
yum update -y >> "$LOG_FILE" 2>&1 || apt-get update >> "$LOG_FILE" 2>&1

# Install CloudWatch agent
log "Installing CloudWatch agent..."
cd /tmp
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" = "amzn" ]; then
    wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
    rpm -U ./amazon-cloudwatch-agent.rpm >> "$LOG_FILE" 2>&1
  else
    wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
    dpkg -i -E ./amazon-cloudwatch-agent.deb >> "$LOG_FILE" 2>&1
  fi
fi

# Install SSM agent
log "Installing SSM agent..."
if ! command -v amazon-ssm-agent &> /dev/null; then
  yum install -y amazon-ssm-agent >> "$LOG_FILE" 2>&1 || apt-get install -y amazon-ssm-agent >> "$LOG_FILE" 2>&1
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
fi

log "Target instance setup completed successfully"
EOF
)

  # Enable detailed monitoring
  monitoring = var.enable_detailed_monitoring

  tags = merge(
    var.common_tags,
    {
      Name              = "${var.project_name}-target-${count.index + 1}"
      Role              = "Application"
      AutoHeal          = "true"
      MonitoringEnabled = "true"
    }
  )

  depends_on = [
    aws_nat_gateway.main
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}

# ============================================================================
# SNS TOPIC FOR ALERTS
# ============================================================================

resource "aws_sns_topic" "auto_heal_alerts" {
  name              = var.sns_topic_name
  display_name      = "Auto-Heal Alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(
    var.common_tags,
    {
      Name = var.sns_topic_name
    }
  )
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "auto_heal_alerts_policy" {
  arn = aws_sns_topic.auto_heal_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.auto_heal_alerts.arn
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.nagios_instance_role.arn
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.auto_heal_alerts.arn
      }
    ]
  })
}

# ============================================================================
# LAMBDA FUNCTION FOR AUTO-HEALING
# ============================================================================

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-lambda-role"
    }
  )
}

# Lambda assume role policy
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# Lambda policy document
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid    = "EC2Permissions"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:RebootInstances",
      "ec2:TerminateInstances",
      "ec2:CreateImage",
      "ec2:CreateTags"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SSMPermissions"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:DescribeDocument"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchPermissions"
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarms"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SNSPermissions"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:Publish"
    ]
    resources = [aws_sns_topic.auto_heal_alerts.arn]
  }

  statement {
    sid    = "CloudWatchLogsPermissions"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"]
  }
}

# CloudWatch Logs Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-auto-heal"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-lambda-logs"
    }
  )
}

# Lambda Function
resource "aws_lambda_function" "auto_heal" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-auto-heal"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "auto_heal_lambda.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN            = aws_sns_topic.auto_heal_alerts.arn
      AUTO_HEALING_ENABLED     = var.auto_healing_enabled
      HEALING_ACTION_TIMEOUT   = var.healing_action_timeout
      MAX_HEALING_ATTEMPTS     = var.max_healing_attempts
      ENABLE_MULTI_REGION      = var.enable_multi_region
      LOG_LEVEL                = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-auto-heal"
    }
  )
}

# Archive Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/auto_heal_lambda.py"
  output_path = "${path.module}/../lambda/auto_heal_lambda.zip"
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.auto_heal_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.auto_heal.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_heal.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.auto_heal_alerts.arn
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# CPU Utilization Alarm (for each target instance)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.target_instance_count
  alarm_name          = "${var.project_name}-cpu-high-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_threshold_cpu
  alarm_description   = "Alert when CPU exceeds ${var.alarm_threshold_cpu}%"
  alarm_actions       = [aws_sns_topic.auto_heal_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.target[count.index].id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-cpu-high-${count.index + 1}"
    }
  )
}

# Instance Status Check Failed Alarm
resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  count               = var.target_instance_count
  alarm_name          = "${var.project_name}-status-check-failed-${count.index + 1}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alert when instance status check fails"
  alarm_actions       = [aws_sns_topic.auto_heal_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.target[count.index].id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-status-check-${count.index + 1}"
    }
  )
}

# Memory Utilization Alarm (requires CloudWatch agent on instance)
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count               = var.enable_detailed_monitoring ? var.target_instance_count : 0
  alarm_name          = "${var.project_name}-memory-high-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = var.project_name
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_threshold_memory
  alarm_description   = "Alert when memory exceeds ${var.alarm_threshold_memory}%"
  alarm_actions       = [aws_sns_topic.auto_heal_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.target[count.index].id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-memory-high-${count.index + 1}"
    }
  )
}

# Disk Utilization Alarm (requires CloudWatch agent on instance)
resource "aws_cloudwatch_metric_alarm" "disk_high" {
  count               = var.enable_detailed_monitoring ? var.target_instance_count : 0
  alarm_name          = "${var.project_name}-disk-high-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DiskUtilization"
  namespace           = var.project_name
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_threshold_disk
  alarm_description   = "Alert when disk exceeds ${var.alarm_threshold_disk}%"
  alarm_actions       = [aws_sns_topic.auto_heal_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.target[count.index].id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-disk-high-${count.index + 1}"
    }
  )
}

# Lambda Error Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when Lambda function has errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.auto_heal.function_name
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-lambda-errors"
    }
  )
}

# ============================================================================
# CLOUDWATCH DASHBOARD (Optional)
# ============================================================================

resource "aws_cloudwatch_dashboard" "auto_heal" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = concat(
            [for i, instance in aws_instance.target : ["AWS/EC2", "CPUUtilization", { InstanceId = instance.id, label = "Instance-${i + 1}-CPU" }]],
            [["AWS/Lambda", "Invocations", { FunctionName = aws_lambda_function.auto_heal.function_name }]],
            [["AWS/Lambda", "Duration", { FunctionName = aws_lambda_function.auto_heal.function_name }]],
            [["AWS/SNS", "NumberOfMessagesPublished", { TopicName = aws_sns_topic.auto_heal_alerts.name }]]
          )
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Auto-Heal Infrastructure Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for i, instance in aws_instance.target :
            ["AWS/EC2", "StatusCheckFailed", { InstanceId = instance.id, label = "Instance-${i + 1}-Status" }]
          ]
          period = 60
          stat   = "Maximum"
          region = var.aws_region
          title  = "Instance Status Checks"
        }
      }
    ]
  })
}
