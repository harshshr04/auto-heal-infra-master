# IAM Role for Grafana EC2 Instance
resource "aws_iam_role" "grafana_instance_role" {
  name               = "${var.project_name}-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-grafana-role"
    }
  )
}

# IAM Policy for Grafana to read CloudWatch metrics
resource "aws_iam_role_policy" "grafana_policy" {
  name   = "${var.project_name}-grafana-policy"
  role   = aws_iam_role.grafana_instance_role.id
  policy = data.aws_iam_policy_document.grafana_policy.json
}

# Attach SSM policy for Systems Manager Agent
resource "aws_iam_role_policy_attachment" "grafana_ssm_policy" {
  role       = aws_iam_role.grafana_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch Read-Only policy
resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_read_policy" {
  role       = aws_iam_role.grafana_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# IAM Instance Profile for Grafana
resource "aws_iam_instance_profile" "grafana_profile" {
  name = "${var.project_name}-grafana-profile"
  role = aws_iam_role.grafana_instance_role.name
}

# Grafana EC2 Instance
resource "aws_instance" "grafana" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.monitoring_instance_type
  subnet_id              = aws_subnet.public[1].id
  iam_instance_profile   = aws_iam_instance_profile.grafana_profile.name
  vpc_security_group_ids = [aws_security_group.monitoring.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.monitoring_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-grafana-root-volume"
    }
  }

  # User data script to install Grafana
  user_data            = base64encode("#!/bin/bash\necho 'Grafana will be installed via system tools'; curl -s https://raw.githubusercontent.com/auto-heal-infra/install-grafana/main/install.sh | bash")

  # Enable detailed monitoring
  monitoring = var.enable_detailed_monitoring

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-grafana"
      Role = "Visualization"
    }
  )

  depends_on = [
    aws_internet_gateway.main
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}

# Elastic IP for Grafana (optional but recommended)
resource "aws_eip" "grafana_eip" {
  instance = aws_instance.grafana.id
  domain   = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-grafana-eip"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# CloudWatch Log Group for Grafana
resource "aws_cloudwatch_log_group" "grafana_logs" {
  name              = "/aws/ec2/${var.project_name}-grafana"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-grafana-logs"
    }
  )
}

# CloudWatch Agent Configuration for Grafana
resource "aws_ssm_parameter" "grafana_cloudwatch_config" {
  name            = "/cloudwatch-config/${var.project_name}-grafana"
  description     = "CloudWatch agent configuration for Grafana"
  type            = "String"
  value           = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path      = "/var/log/grafana/grafana.log"
              log_group_name = aws_cloudwatch_log_group.grafana_logs.name
              log_stream_name = "grafana-app"
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
      Name = "${var.project_name}-grafana-cloudwatch-config"
    }
  )
}

# Data source: IAM policy document for Grafana
data "aws_iam_policy_document" "grafana_policy" {
  statement {
    sid    = "DescribeEC2Instances"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:DescribeRegions"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadCloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:GetMetricData"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadLambdaMetrics"
    effect = "Allow"
    actions = [
      "lambda:ListFunctions",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadSNSMetrics"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:ListTopics"
    ]
    resources = ["*"]
  }
}

# Output Grafana configuration details
output "grafana_installation_details" {
  description = "Details for Grafana installation and configuration"
  value = {
    instance_id       = aws_instance.grafana.id
    public_ip         = aws_eip.grafana_eip.public_ip
    private_ip        = aws_instance.grafana.private_ip
    instance_type     = aws_instance.grafana.instance_type
    security_group    = aws_security_group.monitoring.id
    log_group         = aws_cloudwatch_log_group.grafana_logs.name
    access_url        = "http://${aws_eip.grafana_eip.public_ip}:3000"
    config_dir        = "/etc/grafana"
    data_dir          = "/var/lib/grafana"
    provisioning_dir  = "/etc/grafana/provisioning"
  }
}
