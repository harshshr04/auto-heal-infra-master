# Auto-Heal Infrastructure - Deployment Guide

Complete step-by-step guide for deploying the Auto-Heal Infrastructure on AWS.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Setup](#pre-deployment-setup)
3. [Terraform Deployment](#terraform-deployment)
4. [Post-Deployment Verification](#post-deployment-verification)
5. [Nagios Configuration](#nagios-configuration)
6. [Grafana Setup](#grafana-setup)
7. [Testing & Validation](#testing--validation)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

- **Terraform** 1.0+ - [Install](https://www.terraform.io/downloads.html)
- **AWS CLI** v2 - [Install](https://aws.amazon.com/cli/)
- **Git** - [Install](https://git-scm.com/)
- **SSH Client** - For connecting to EC2 instances
- **Text Editor** - VS Code, Vim, Nano, etc.

### AWS Account Requirements

- Active AWS Account with appropriate permissions
- IAM User or Role with:
  - EC2 full access
  - Lambda full access
  - SNS full access
  - CloudWatch full access
  - IAM role creation permissions
  - VPC and networking permissions
  - Systems Manager permissions

### AWS Credentials

Configure AWS credentials before deployment:

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter your default region (e.g., us-east-1)
# Enter default output format (json recommended)
```

Or use environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

---

## Pre-Deployment Setup

### Step 1: Clone the Repository

```bash
cd ~/Desktop/Devops
git clone <repository-url> auto-heal-infra
cd auto-heal-infra
```

### Step 2: Review Project Structure

```bash
tree -L 3 terraform/
```

Verify the following directories and files exist:
- `terraform/main.tf`
- `terraform/variables.tf`
- `terraform/outputs.tf`
- `terraform/providers.tf`
- `terraform/monitoring_sg.tf`
- `terraform/nagios_ec2.tf`
- `terraform/grafana_ec2.tf`
- `lambda/auto_heal_lambda.py`
- `scripts/heal_instance.sh`
- `scripts/install_nagios.sh`
- `scripts/install_grafana.sh`
- `scripts/target_user_data.sh`

### Step 3: Create Terraform Variables File

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### Step 4: Configure Variables

Edit `terraform.tfvars` with your specific configuration:

```bash
vim terraform.tfvars
```

**Important variables to customize:**

```hcl
aws_region = "us-east-1"              # Your target region
environment = "dev"                    # dev, staging, or prod
project_name = "auto-heal-infra"      # Project identifier

# Instance configuration
target_instance_count = 2              # Number of target instances
instance_type = "t3.medium"            # Instance type
monitoring_instance_type = "t3.medium" # For Nagios/Grafana

# Alarm thresholds
alarm_threshold_cpu = 80               # CPU threshold %
alarm_threshold_memory = 85            # Memory threshold %
alarm_threshold_disk = 90              # Disk threshold %

# Credentials (CHANGE IN PRODUCTION!)
nagios_password = "nagios"
grafana_admin_password = "admin"

# Optional: Remote state
# Uncomment after creating S3 bucket and DynamoDB table
```

### Step 5: Create S3 Backend (Optional but Recommended)

For remote state management:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
    --bucket auto-heal-infra-state-$(aws sts get-caller-identity --query Account --output text) \
    --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket auto-heal-infra-state-$(aws sts get-caller-identity --query Account --output text) \
    --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
    --table-name terraform-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
```

---

## Terraform Deployment

### Step 1: Initialize Terraform

```bash
cd terraform

# Without remote backend
terraform init

# With remote backend (after creating S3 + DynamoDB)
terraform init \
    -backend-config="bucket=auto-heal-infra-state-$(aws sts get-caller-identity --query Account --output text)" \
    -backend-config="key=auto-heal-infra/terraform.tfstate" \
    -backend-config="region=us-east-1" \
    -backend-config="encrypt=true" \
    -backend-config="dynamodb_table=terraform-locks"
```

### Step 2: Validate Configuration

```bash
terraform validate
```

Expected output: ✓ Success! The configuration is valid.

### Step 3: Format Code (Optional)

```bash
terraform fmt -recursive
```

### Step 4: Plan Deployment

```bash
terraform plan -out=tfplan

# Review the output carefully
# Verify:
# - Number of resources to be created (should be 50+)
# - VPC and subnet creation
# - EC2 instances (target + Nagios + Grafana)
# - Lambda function
# - CloudWatch alarms
# - SNS topics
```

### Step 5: Apply Configuration

```bash
terraform apply tfplan

# This will take 5-10 minutes
# Watch for:
# - VPC creation
# - EC2 instance launches
# - Security group creation
# - IAM role creation
# - Lambda function deployment
```

### Step 6: Retrieve Outputs

```bash
terraform output

# Save important outputs:
terraform output nagios_public_ip
terraform output grafana_public_ip
terraform output target_instance_ids
terraform output lambda_function_arn
terraform output sns_topic_arn
```

---

## Post-Deployment Verification

### Step 1: Verify AWS Resources

```bash
# Check EC2 instances
aws ec2 describe-instances --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]' --output table

# Check Lambda function
aws lambda get-function --function-name auto-heal-infra-auto-heal

# Check SNS topic
aws sns list-topics | grep auto-heal

# Check CloudWatch alarms
aws cloudwatch describe-alarms --query 'MetricAlarms[].AlarmName' --output table
```

### Step 2: Verify Network Connectivity

```bash
# Test SSH to Nagios instance
NAGIOS_IP=$(terraform output -raw nagios_public_ip)
ssh -i <your-key-pair.pem> ec2-user@$NAGIOS_IP "echo 'SSH Success'"

# Test SSH to Grafana instance
GRAFANA_IP=$(terraform output -raw grafana_public_ip)
ssh -i <your-key-pair.pem> ec2-user@$GRAFANA_IP "echo 'SSH Success'"

# Test SSH to target instance
TARGET_IP=$(terraform output -json target_instance_ids | jq -r '.[0]')
# Get private IP and test from within VPC or via Systems Manager
aws ssm start-session --target $(terraform output -json target_instance_ids | jq -r '.[0]')
```

### Step 3: Check Installation Progress

Wait 5-10 minutes for user data scripts to complete, then check logs:

```bash
# Nagios installation log
ssh -i <key.pem> ec2-user@$NAGIOS_IP "tail -50 /var/log/nagios-install.log"

# Grafana installation log
ssh -i <key.pem> ec2-user@$GRAFANA_IP "tail -50 /var/log/grafana-install.log"

# Target instance setup log
aws ssm start-session --target $(terraform output -json target_instance_ids | jq -r '.[0]')
# Inside the session:
tail -50 /var/log/auto-heal/user_data.log
```

---

## Nagios Configuration

### Step 1: Access Nagios Dashboard

```
URL: http://<nagios_public_ip>/nagios
Username: nagiosadmin
Password: nagios
```

### Step 2: Change Default Password

```bash
ssh -i <key.pem> ec2-user@<nagios_public_ip>

# Change Nagios admin password
sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin
# Enter new password twice
```

### Step 3: Add Target Instances to Nagios

```bash
# Connect to Nagios instance
ssh -i <key.pem> ec2-user@<nagios_public_ip>

# Edit Nagios configuration
sudo vi /usr/local/nagios/etc/objects/localhost.cfg

# Add target instances:
define host {
    use                 linux-server
    host_name           target-instance-1
    address             <target-instance-private-ip>
    hostgroups          auto_heal_instances
    check_interval      5
}

define service {
    use                 local-service
    host_name           target-instance-1
    service_description NRPE Check CPU
    check_command       check_nrpe!check_load
    check_interval      5
}

define service {
    use                 local-service
    host_name           target-instance-1
    service_description HTTP Check
    check_command       check_http
    check_interval      5
}
```

### Step 4: Add Hostgroup

```bash
# In the same configuration file, add:
define hostgroup {
    hostgroup_name      auto_heal_instances
    alias               Auto-Heal Target Instances
    members             target-instance-1,target-instance-2
}
```

### Step 5: Verify and Reload Configuration

```bash
# Verify configuration syntax
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

# If no errors, reload Nagios
sudo systemctl reload nagios

# Check Nagios status
sudo systemctl status nagios
```

### Step 6: Setup SNS Integration (Optional)

To enable Nagios to trigger Lambda via SNS:

```bash
# Create notification script
sudo tee /usr/local/nagios/libexec/notify_sns.sh > /dev/null << 'EOF'
#!/bin/bash
SNS_TOPIC_ARN="<your-sns-topic-arn>"
INSTANCE_ID="$1"
ACTION="$2"

aws sns publish \
    --topic-arn "$SNS_TOPIC_ARN" \
    --message "Nagios Alert: $ACTION for $INSTANCE_ID" \
    --region us-east-1
EOF

sudo chmod +x /usr/local/nagios/libexec/notify_sns.sh

# Add to Nagios contact definition
sudo vi /usr/local/nagios/etc/objects/contacts.cfg
# Update nagiosadmin contact with service_notification_commands and host_notification_commands
```

---

## Grafana Setup

### Step 1: Access Grafana Dashboard

```
URL: http://<grafana_public_ip>:3000
Username: admin
Password: admin
```

### Step 2: Change Default Password

1. Click on user icon (bottom left) → Profile
2. Click "Change password"
3. Enter old password: `admin`
4. Enter new password (strong)
5. Confirm

### Step 3: Add CloudWatch Data Source

1. Go to Configuration (left menu) → Data Sources
2. Click "Add data source"
3. Select "CloudWatch"
4. Configure:
   - **Name**: CloudWatch
   - **Default Region**: us-east-1 (or your region)
   - **Access**: Server (default)
   - **Auth Provider**: Default AWS credentials (uses IAM role)
5. Click "Save & Test"
6. You should see "Successfully queried the CloudWatch API"

### Step 4: Import Dashboards

Pre-created dashboards should be available in `/var/lib/grafana/dashboards/`:

1. Go to Dashboards (left menu) → Manage
2. Click "Import"
3. Upload the dashboard JSON files or copy-paste:
   - `infrastructure-overview.json`
   - `healing-activity.json`

### Step 5: Create Custom Dashboards (Optional)

Create new dashboards to monitor:

1. **Infrastructure Health**:
   - EC2 instance status
   - CPU utilization
   - Memory utilization
   - Disk utilization

2. **Healing Activity**:
   - Lambda invocations
   - Healing success/failure rates
   - SNS message count
   - Healing action timeline

---

## Testing & Validation

### Test 1: Verify Lambda Invocation

```bash
# Send test message to SNS
TOPIC_ARN=$(terraform output -raw sns_topic_arn)
INSTANCE_ID=$(terraform output -json target_instance_ids | jq -r '.[0]')

aws sns publish \
    --topic-arn "$TOPIC_ARN" \
    --message "{\"AlarmName\":\"test-cpu-alarm\",\"Trigger\":{\"MetricName\":\"CPUUtilization\",\"Dimensions\":{\"InstanceId\":\"$INSTANCE_ID\"}}}" \
    --region us-east-1

# Check Lambda logs
aws logs tail /aws/lambda/auto-heal-infra-auto-heal --follow
```

### Test 2: Verify CloudWatch Metrics

```bash
# Query CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID
```

### Test 3: Verify Systems Manager Access

```bash
# Test SSM command execution
INSTANCE_ID=$(terraform output -json target_instance_ids | jq -r '.[0]')

aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["echo \"SSM Test Success\"; uname -a"]' \
    --output text

# Get command output
aws ssm get-command-invocation \
    --command-id <command-id-from-above> \
    --instance-id "$INSTANCE_ID" \
    --output text
```

### Test 4: Trigger Simulated Alarm

```bash
# Create temporary high CPU load
INSTANCE_ID=$(terraform output -json target_instance_ids | jq -r '.[0]')

aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["stress --cpu 2 --timeout 60s"]' \
    --output text
```

---

## Troubleshooting

### Issue: Terraform Plan/Apply Fails

**Check 1: AWS Credentials**
```bash
aws sts get-caller-identity
```

**Check 2: Terraform Syntax**
```bash
terraform validate
terraform fmt -recursive
```

**Check 3: Variables File**
```bash
# Ensure terraform.tfvars exists and is properly formatted
cat terraform.tfvars | head -20
```

### Issue: EC2 Instances Not Starting

```bash
# Check instance status
aws ec2 describe-instance-status --instance-ids <instance-id>

# Check CloudWatch logs
aws logs tail /aws/ec2/<instance-name> --follow

# SSH to instance and check user data logs
ssh -i <key.pem> ec2-user@<public-ip>
tail -100 /var/log/cloud-init-output.log
```

### Issue: Nagios Shows "Could Not Parse Host Definition"

```bash
# Validate Nagios config
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

# Check config file syntax
sudo cat /usr/local/nagios/etc/objects/localhost.cfg | grep -A 5 "define host"
```

### Issue: Grafana Can't Connect to CloudWatch

```bash
# Check IAM role permissions
aws iam get-role --role-name auto-heal-infra-grafana-role

# Check CloudWatch agent on Grafana instance
ssh -i <key.pem> ec2-user@<grafana-ip>
systemctl status grafana-server
tail -50 /var/log/grafana/grafana.log
```

### Issue: Lambda Not Receiving SNS Messages

```bash
# Check SNS subscription
aws sns list-subscriptions-by-topic --topic-arn <sns-topic-arn>

# Check Lambda permissions
aws lambda get-policy --function-name auto-heal-infra-auto-heal

# Check Lambda logs
aws logs tail /aws/lambda/auto-heal-infra-auto-heal --follow
```

---

## Cleanup

To destroy all resources:

```bash
cd terraform

# Plan destruction
terraform plan -destroy

# Execute destruction
terraform destroy

# Confirm by typing 'yes'
```

---

## Next Steps

1. **Configure Production Settings**:
   - Change all default passwords
   - Update CIDR blocks for security groups
   - Enable MFA for AWS console
   - Set up cross-account roles if needed

2. **Add Monitoring Alerts**:
   - Configure Nagios notification contacts
   - Set up Grafana alerting channels (Slack, PagerDuty, etc.)
   - Configure CloudWatch SNS subscriptions

3. **Implement Custom Healing Logic**:
   - Customize `auto_heal_lambda.py` for your use cases
   - Add custom healing actions to `heal_instance.sh`
   - Create additional Nagios service checks

4. **Documentation & Training**:
   - Document custom configurations
   - Train team on Nagios/Grafana dashboards
   - Create runbooks for common issues

---

## Support & Resources

- **AWS Documentation**: https://docs.aws.amazon.com
- **Terraform Documentation**: https://www.terraform.io/docs
- **Nagios Documentation**: https://www.nagios.org/documentation
- **Grafana Documentation**: https://grafana.com/docs

---

**Happy Healing! 🚀**
