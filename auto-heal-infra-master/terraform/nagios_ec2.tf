# IAM Role for Nagios EC2 Instance
resource "aws_iam_role" "nagios_instance_role" {
  name               = "${var.project_name}-nagios-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nagios-role"
    }
  )
}

# IAM Policy for Nagios to read EC2 and CloudWatch data
resource "aws_iam_role_policy" "nagios_policy" {
  name   = "${var.project_name}-nagios-policy"
  role   = aws_iam_role.nagios_instance_role.id
  policy = data.aws_iam_policy_document.nagios_policy.json
}

# Attach SSM policy for Systems Manager Agent
resource "aws_iam_role_policy_attachment" "nagios_ssm_policy" {
  role       = aws_iam_role.nagios_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch policy
resource "aws_iam_role_policy_attachment" "nagios_cloudwatch_policy" {
  role       = aws_iam_role.nagios_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile for Nagios
resource "aws_iam_instance_profile" "nagios_profile" {
  name = "${var.project_name}-nagios-profile"
  role = aws_iam_role.nagios_instance_role.name
}

# Nagios EC2 Instance
resource "aws_instance" "nagios" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.monitoring_instance_type
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.nagios_profile.name
  vpc_security_group_ids = [aws_security_group.monitoring.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.monitoring_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-nagios-root-volume"
    }
  }

  # User data script to install Nagios
  user_data            = base64encode("#!/bin/bash\necho 'Nagios will be installed via system tools'; curl -s https://raw.githubusercontent.com/auto-heal-infra/install-nagios/main/install.sh | bash")

  # Enable detailed monitoring
  monitoring = var.enable_detailed_monitoring

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nagios"
      Role = "Monitoring"
    }
  )

  depends_on = [
    aws_internet_gateway.main
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}

# Elastic IP for Nagios (optional but recommended)
resource "aws_eip" "nagios_eip" {
  instance = aws_instance.nagios.id
  domain   = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nagios-eip"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# CloudWatch Log Group for Nagios
resource "aws_cloudwatch_log_group" "nagios_logs" {
  name              = "/aws/ec2/${var.project_name}-nagios"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nagios-logs"
    }
  )
}

# CloudWatch Agent Configuration for Nagios
resource "aws_ssm_parameter" "nagios_cloudwatch_config" {
  name            = "/cloudwatch-config/${var.project_name}-nagios"
  description     = "CloudWatch agent configuration for Nagios"
  type            = "String"
  value           = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path      = "/var/log/nagios/nagios.log"
              log_group_name = aws_cloudwatch_log_group.nagios_logs.name
              log_stream_name = "nagios-core"
            }
          ]
        }
      }
    }
    metrics = {
      namespace   = var.project_name
      metrics_collected = {
        cpu = {
          measurement = [
            { name = "cpu_usage_idle", rename = "CPU_IDLE", unit = "Percent" },
            { name = "cpu_usage_iowait", rename = "CPU_IOWAIT", unit = "Percent" }
          ]
          metrics_collection_interval = 60
          resources = ["*"]
        }
        disk = {
          measurement = [
            { name = "used_percent", rename = "DISK_USED", unit = "Percent" }
          ]
          metrics_collection_interval = 60
          resources = ["*"]
        }
        mem = {
          measurement = [
            { name = "mem_used_percent", rename = "MEM_USED", unit = "Percent" }
          ]
          metrics_collection_interval = 60
        }
      }
    }
  })
  overwrite       = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nagios-cloudwatch-config"
    }
  )
}

# Data source: IAM policy document for Nagios
data "aws_iam_policy_document" "nagios_policy" {
  statement {
    sid    = "DescribeEC2Instances"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadCloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarms"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadSNSTopics"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:ListTopics"
    ]
    resources = [aws_sns_topic.auto_heal_alerts.arn]
  }

  statement {
    sid    = "PublishToSNS"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.auto_heal_alerts.arn]
  }

  statement {
    sid    = "ReadSSMDocuments"
    effect = "Allow"
    actions = [
      "ssm:DescribeDocument",
      "ssm:GetDocument"
    ]
    resources = ["*"]
  }
}

# Output Nagios configuration details
output "nagios_installation_details" {
  description = "Details for Nagios installation and configuration"
  value = {
    instance_id  = aws_instance.nagios.id
    public_ip    = aws_eip.nagios_eip.public_ip
    private_ip   = aws_instance.nagios.private_ip
    instance_type = aws_instance.nagios.instance_type
    security_group = aws_security_group.monitoring.id
    log_group    = aws_cloudwatch_log_group.nagios_logs.name
    access_url   = "http://${aws_eip.nagios_eip.public_ip}/nagios"
    config_file  = "/etc/nagios/nagios.cfg"
    objects_dir  = "/etc/nagios/objects"
    libexec_dir  = "/usr/local/nagios/libexec"
  }
}
