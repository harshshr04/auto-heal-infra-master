output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

# Target EC2 Instances
output "target_instance_ids" {
  description = "IDs of target EC2 instances"
  value       = aws_instance.target[*].id
}

output "target_instance_private_ips" {
  description = "Private IP addresses of target instances"
  value       = aws_instance.target[*].private_ip
}

output "target_instance_public_ips" {
  description = "Public IP addresses of target instances"
  value       = aws_instance.target[*].public_ip
}

# Nagios EC2 Instance
output "nagios_instance_id" {
  description = "Nagios EC2 instance ID"
  value       = aws_instance.nagios.id
}

output "nagios_public_ip" {
  description = "Nagios EC2 public IP address"
  value       = aws_instance.nagios.public_ip
}

output "nagios_private_ip" {
  description = "Nagios EC2 private IP address"
  value       = aws_instance.nagios.private_ip
}

output "nagios_access_url" {
  description = "URL to access Nagios dashboard"
  value       = "http://${aws_instance.nagios.public_ip}/nagios"
}

output "nagios_credentials" {
  description = "Nagios access credentials (CHANGE IMMEDIATELY IN PRODUCTION)"
  value = {
    username = "nagiosadmin"
    password = "⚠️  Default: nagios (CHANGE ASAP)"
  }
  sensitive = true
}

# Grafana EC2 Instance
output "grafana_instance_id" {
  description = "Grafana EC2 instance ID"
  value       = aws_instance.grafana.id
}

output "grafana_public_ip" {
  description = "Grafana EC2 public IP address"
  value       = aws_instance.grafana.public_ip
}

output "grafana_private_ip" {
  description = "Grafana EC2 private IP address"
  value       = aws_instance.grafana.private_ip
}

output "grafana_access_url" {
  description = "URL to access Grafana dashboard"
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}

output "grafana_credentials" {
  description = "Grafana access credentials (CHANGE IMMEDIATELY IN PRODUCTION)"
  value = {
    username = "admin"
    password = "⚠️  Default: admin (CHANGE ASAP)"
  }
  sensitive = true
}

# Lambda Function
output "lambda_function_name" {
  description = "Name of the auto-heal Lambda function"
  value       = aws_lambda_function.auto_heal.function_name
}

output "lambda_function_arn" {
  description = "ARN of the auto-heal Lambda function"
  value       = aws_lambda_function.auto_heal.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Logs group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# SNS Topic
output "sns_topic_arn" {
  description = "ARN of SNS topic for alerts"
  value       = aws_sns_topic.auto_heal_alerts.arn
}

output "sns_topic_name" {
  description = "Name of SNS topic"
  value       = aws_sns_topic.auto_heal_alerts.name
}

# Security Groups
output "target_security_group_id" {
  description = "Security group ID for target instances"
  value       = aws_security_group.target_instances.id
}

output "monitoring_security_group_id" {
  description = "Security group ID for Nagios and Grafana"
  value       = aws_security_group.monitoring.id
}

# IAM Roles
output "target_instance_role_arn" {
  description = "ARN of IAM role for target instances"
  value       = aws_iam_role.target_instance_role.arn
}

output "target_instance_profile_arn" {
  description = "ARN of IAM instance profile for target instances"
  value       = aws_iam_instance_profile.target_instance_profile.arn
}

output "nagios_instance_role_arn" {
  description = "ARN of IAM role for Nagios instance"
  value       = aws_iam_role.nagios_instance_role.arn
}

output "grafana_instance_role_arn" {
  description = "ARN of IAM role for Grafana instance"
  value       = aws_iam_role.grafana_instance_role.arn
}

# CloudWatch Alarms
output "cpu_alarm_name" {
  description = "Name of CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_high[0].alarm_name
}

output "memory_alarm_name" {
  description = "Name of memory utilization alarm"
  value       = try(aws_cloudwatch_metric_alarm.memory_high[0].alarm_name, "N/A - Requires CloudWatch Agent")
}

output "disk_alarm_name" {
  description = "Name of disk utilization alarm"
  value       = try(aws_cloudwatch_metric_alarm.disk_high[0].alarm_name, "N/A - Requires CloudWatch Agent")
}

output "status_check_alarm_name" {
  description = "Name of instance status check alarm"
  value       = aws_cloudwatch_metric_alarm.status_check_failed[0].alarm_name
}

# CloudWatch Dashboard
output "cloudwatch_dashboard_url" {
  description = "URL to access CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=auto-heal-dashboard" : "Not enabled"
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    vpc_id                  = aws_vpc.main.id
    target_instances        = length(aws_instance.target)
    nagios_instance_id      = aws_instance.nagios.id
    grafana_instance_id     = aws_instance.grafana.id
    lambda_function_name    = aws_lambda_function.auto_heal.function_name
    sns_topic_arn          = aws_sns_topic.auto_heal_alerts.arn
    cloudwatch_alarms       = length(aws_cloudwatch_metric_alarm.cpu_high) + length(aws_cloudwatch_metric_alarm.status_check_failed)
    total_security_groups   = 2
    total_iam_roles         = 3
  }
}

# Post-Deployment Access Instructions
output "post_deployment_instructions" {
  description = "Post-deployment configuration steps"
  value = <<-EOT
    
    🎯 AUTO-HEAL INFRASTRUCTURE DEPLOYMENT COMPLETE!
    
    ═════════════════════════════════════════════════════════════
    
    📊 MONITORING DASHBOARDS:
    
    1. Nagios Dashboard:
       URL: http://${aws_instance.nagios.public_ip}/nagios
       Default Username: nagiosadmin
       Default Password: nagios
       ⚠️  CHANGE PASSWORD IMMEDIATELY IN PRODUCTION
    
    2. Grafana Dashboard:
       URL: http://${aws_instance.grafana.public_ip}:3000
       Default Username: admin
       Default Password: admin
       ⚠️  CHANGE PASSWORD IMMEDIATELY IN PRODUCTION
    
    ═════════════════════════════════════════════════════════════
    
    🔧 NEXT STEPS:
    
    1. SSH into Nagios instance and configure hosts:
       ssh -i <key-pair> ec2-user@${aws_instance.nagios.public_ip}
       Edit: /etc/nagios/objects/localhost.cfg
       Add target instance IPs: ${join(", ", aws_instance.target[*].private_ip)}
    
    2. Configure Grafana data sources:
       - Add CloudWatch as data source
       - Create dashboards for monitoring
    
    3. Test Lambda function with SNS message:
       aws sns publish --topic-arn ${aws_sns_topic.auto_heal_alerts.arn} \
         --message '{"instance_id":"${aws_instance.target[0].id}","action":"reboot"}'
    
    4. Monitor healing actions:
       - Check CloudWatch Logs: ${aws_cloudwatch_log_group.lambda_logs.name}
       - Review SNS message history
       - Check instance status in EC2 console
    
    ═════════════════════════════════════════════════════════════
    
    📝 DOCUMENTATION:
    - See README.md for comprehensive project documentation
    - Review lambda/auto_heal_lambda.py for healing logic
    - Check scripts/ for installation and healing scripts
    
    ═════════════════════════════════════════════════════════════
  EOT
}
