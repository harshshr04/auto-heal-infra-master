# Auto-Heal Infrastructure on AWS

A comprehensive, self-healing AWS infrastructure solution that automatically detects and remediates unhealthy EC2 instances and services. Built with Terraform, Nagios, Grafana, AWS Lambda, and CloudWatch.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Core Logic & Automation](#core-logic--automation)
4. [AWS Services](#aws-services)
5. [Infrastructure as Code (IaC)](#infrastructure-as-code-iac)
6. [Monitoring & Visualization](#monitoring--visualization)
7. [Deployment Guide](#deployment-guide)
8. [Post-Deployment Configuration](#post-deployment-configuration)
9. [Project Structure](#project-structure)
10. [Accessing Nagios and Grafana](#accessing-nagios-and-grafana)
11. [Best Practices & Security](#best-practices--security)
12. [Troubleshooting](#troubleshooting)

---

## Project Overview

### Goal
Create a self-healing AWS infrastructure that automatically addresses issues such as:
- EC2 instance failures
- Service crashes
- Resource exhaustion (CPU, memory, disk)
- Unhealthy instance status checks

### Key Features
- **Automated Detection**: CloudWatch alarms and Nagios plugins monitor instances 24/7
- **Intelligent Remediation**: Lambda-driven healing actions (reboot, replace, or execute custom scripts)
- **Real-time Visualization**: Nagios and Grafana dashboards for monitoring and healing activity tracking
- **Infrastructure as Code**: Fully automated provisioning via Terraform
- **Scalable Design**: Modular Terraform for easy expansion and multi-region support

---

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Account                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐         ┌──────────────────────┐    │
│  │  Target EC2          │         │  Monitoring EC2      │    │
│  │  Instances           │◄────────┤  Stack:              │    │
│  │  (Auto Scaling)      │         │  - Nagios Core       │    │
│  │                      │         │  - Grafana           │    │
│  │  - CloudWatch Agent  │         │  - Data Collection   │    │
│  │  - SSM Agent         │         └──────────────────────┘    │
│  │  - Custom Apps       │                    ▲                │
│  └──────────────────────┘                    │                │
│           ▲                                   │                │
│           │                         ┌─────────┴──────────┐    │
│           │                         │  CloudWatch        │    │
│           │                         │  - Alarms          │    │
│           │                         │  - Metrics         │    │
│           │                         │  - Dashboard       │    │
│           │                         └─────────┬──────────┘    │
│           │                                   │                │
│           │                         ┌─────────▼──────────┐    │
│           │                         │  SNS Topic         │    │
│           │                         │  (Notifications)   │    │
│           │                         └─────────┬──────────┘    │
│           │                                   │                │
│           │                    ┌──────────────▼──────────┐    │
│           │                    │  AWS Lambda            │    │
│           │                    │  auto_heal_lambda.py   │    │
│           │                    │  - Parse Alarms        │    │
│           │                    │ - Decide Healing Action│    │
│           │                    │ - Execute via SSM      │    │
│           │                    └──────────────┬─────────┘    │
│           │                                   │                │
│           └───────────────┐    ┌──────────────▼──────────┐    │
│                           │    │  Systems Manager (SSM) │    │
│                           │    │  - Run Commands        │    │
│                           │    │ - Execute heal_instance│    │
│                           │    └────────────────────────┘    │
│                           │                                   │
│           ┌───────────────▼──────────────┐                   │
│           │  heal_instance.sh            │                   │
│           │  - Restart Services          │                   │
│           │  - Clear Caches              │                   │
│           │  - Custom Healing Actions    │                   │
│           └────────────────────────────┘                   │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐  │
│  │  IAM Roles       │  │  Security Groups │  │  VPC/      │  │
│  │  & Policies      │  │  (Firewall Rules)│  │  Networking│  │
│  └──────────────────┘  └──────────────────┘  └────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Detection Phase**:
   - CloudWatch Alarms monitor EC2 instance status checks and metrics
   - Nagios plugins perform active checks on instances and services
   - Both can trigger SNS notifications

2. **Alert Phase**:
   - SNS topic receives alerts from CloudWatch and/or Nagios
   - Notifications are routed to Lambda function

3. **Decision & Healing Phase**:
   - Lambda function (`auto_heal_lambda.py`) receives SNS message
   - Parses alert details and determines appropriate healing action
   - Executes healing via AWS Systems Manager (SSM)

4. **Execution Phase**:
   - SSM Run Command executes `heal_instance.sh` on target instances
   - Script performs healing actions (restart services, clear caches, etc.)

5. **Visualization Phase**:
   - Grafana displays real-time metrics and healing activity
   - Nagios dashboard shows instance and service status

---

## Core Logic & Automation

### AWS Lambda: `auto_heal_lambda.py`
The heart of the auto-healing system.

**Responsibilities**:
- **Parse SNS Messages**: Extract instance ID, alarm type, and metrics from CloudWatch alarms or Nagios alerts
- **Decide Healing Action**: 
  - **CPU High**: Execute custom script to optimize processes
  - **Memory High**: Clear caches, restart non-critical services
  - **Disk Full**: Clean logs, clear temp files
  - **Instance Status Check Failed**: Reboot instance
  - **Service Down**: Restart service via SSM
- **Execute Healing**: Use boto3 to call AWS APIs (EC2, SSM)
- **Logging**: Track all healing actions for audit and debugging

**Triggering Mechanisms**:
- CloudWatch Alarms → SNS → Lambda
- Nagios Webhooks → SNS → Lambda (via SNS integration)

### Bash Healing Script: `heal_instance.sh`
Executed on target instances via AWS Systems Manager.

**Actions**:
- `restart_service`: Restart specific service (e.g., `systemctl restart nginx`)
- `clear_cache`: Clear OS-level caches (`sync; echo 3 > /proc/sys/vm/drop_caches`)
- `cleanup_logs`: Compress and archive old logs
- `disk_cleanup`: Remove old files and temporary data
- Custom healing logic as needed

### Installation Scripts
- **`install_nagios.sh`**: Installs Nagios Core, plugins, and configuration on Ubuntu/Amazon Linux 2
- **`install_grafana.sh`**: Installs Grafana, configures data sources, and creates dashboards

---

## AWS Services

### 1. **Amazon EC2**
- **Target Instances**: Application servers to be monitored and healed
- **Nagios EC2**: Dedicated instance for Nagios Core
- **Grafana EC2**: Dedicated instance for Grafana
- **Features Used**: Instance status checks, CloudWatch agent, SSM agent

### 2. **Amazon CloudWatch**
- **Metrics**: CPU utilization, memory, disk, network
- **Alarms**: Triggers remediation when thresholds exceeded
- **Logs**: Centralized logging for Lambda and instance scripts
- **Dashboard**: Optional hybrid monitoring dashboard

### 3. **Amazon SNS (Simple Notification Service)**
- **Topics**: Central notification hub
- **Publishers**: CloudWatch Alarms, Nagios webhooks
- **Subscribers**: Lambda function
- **Use**: Decouples monitoring from healing logic

### 4. **AWS Systems Manager (SSM)**
- **Session Manager**: Secure shell access to instances
- **Run Command**: Execute scripts on instances without SSH
- **Parameter Store**: Store configuration values securely
- **Use**: Execute `heal_instance.sh` on target instances

### 5. **AWS Lambda**
- **Function**: `auto_heal_lambda.py`
- **Trigger**: SNS events
- **Runtime**: Python 3.11+
- **Permissions**: EC2, SSM, SNS, CloudWatch Logs

### 6. **AWS IAM**
- **Roles**: Separate roles for Lambda, EC2 instances, Nagios/Grafana
- **Policies**: Least-privilege access to AWS resources
- **Profiles**: EC2 Instance Profiles for attached roles

### 7. **AWS Regions API**
- **Use**: Optional multi-region instance scanning
- **Endpoint**: `ec2:DescribeRegions`

---

## Infrastructure as Code (IaC)

All infrastructure is managed via **Terraform**.

### Terraform File Structure

```
terraform/
├── main.tf                      # Main resource definitions
├── variables.tf                 # Input variables
├── outputs.tf                   # Output values
├── providers.tf                 # AWS provider configuration
├── monitoring_sg.tf             # Security Groups for monitoring
├── nagios_ec2.tf                # Nagios EC2 instance & IAM
├── grafana_ec2.tf               # Grafana EC2 instance & IAM
├── backend/
│   └── backend.tf               # Remote state configuration
└── modules/
    ├── ec2_instance/            # Reusable EC2 module
    ├── lambda_function/         # Lambda deployment module
    └── sns_topic/               # SNS topic module
```

### Key Terraform Files

#### `providers.tf`
- AWS provider configuration
- Region, credentials, default tags

#### `variables.tf`
- Input variables for environment, region, instance type, etc.
- Configurable thresholds for alarms

#### `main.tf`
- Target EC2 instances
- CloudWatch alarms
- Lambda function
- SNS topics
- IAM roles and policies

#### `monitoring_sg.tf`
- Security Group for Nagios EC2 (ports 80, 5667 for NRPE)
- Security Group for Grafana EC2 (ports 80, 443)
- Inbound rules for monitoring traffic
- Outbound rules for EC2 access

#### `nagios_ec2.tf`
- EC2 instance for Nagios Core
- IAM role and instance profile for EC2 access
- User data script execution (`install_nagios.sh`)
- EBS volume configuration
- Network interface setup

#### `grafana_ec2.tf`
- EC2 instance for Grafana
- IAM role and instance profile for CloudWatch access
- User data script execution (`install_grafana.sh`)
- EBS volume configuration
- Network interface setup

#### Modules

**`modules/ec2_instance/`**
- Reusable EC2 module for target application instances
- Includes CloudWatch agent setup
- SSM agent configuration
- IAM instance profile

**`modules/lambda_function/`**
- Lambda function packaging and deployment
- IAM role and execution policy
- VPC configuration (optional)

**`modules/sns_topic/`**
- SNS topic creation
- Subscription management
- Access policies

---

## Monitoring & Visualization

### Nagios Core (on Dedicated EC2)

**Purpose**: Real-time EC2 health monitoring and alert triggering.

**Installation**:
- Deployed via `install_nagios.sh` as EC2 user data
- Installed on dedicated Ubuntu/Amazon Linux 2 instance
- Accessible on port 80/443 (via HTTP/HTTPS)

**Configuration**:
- **Host Definitions**: EC2 instances added to Nagios
- **Service Checks**:
  - `check_ec2_instance_status`: AWS API check via Nagios plugins
  - `check_nrpe`: Remote execution on instances (CPU, Memory, Disk via SSM)
  - `check_http`/`check_tcp`: Application-level checks
- **Alert Handlers**: Nagios can execute webhooks/scripts to trigger SNS

**Dashboards**:
- Service status page
- Host status overview
- Alert history
- Performance graphs

**Access**:
- URL: `http://<nagios-ec2-public-ip>/nagios`
- Default credentials: `nagiosadmin` / `nagios` (⚠️ **Change immediately in production**)

### Grafana (on Dedicated EC2)

**Purpose**: Interactive, aesthetic dashboards for real-time metrics and healing activity.

**Installation**:
- Deployed via `install_grafana.sh` as EC2 user data
- Installed on dedicated Ubuntu/Amazon Linux 2 instance
- Accessible on port 3000

**Data Sources**:
- **AWS CloudWatch**: Native AWS metrics (CPU, Network, Disk)
- **Prometheus** (optional): For detailed system metrics
- **Nagios** (optional): Direct Nagios data source plugin

**Dashboards**:
1. **Instance Health Overview**:
   - EC2 instance status (running, stopped, status checks)
   - Instance count by region
   - Unhealthy instance alerts

2. **Metrics Dashboard**:
   - CPU utilization time-series
   - Memory usage trends
   - Disk space utilization
   - Network bandwidth

3. **Healing Activity Timeline**:
   - Recent healing actions
   - Success/failure rates
   - Time to heal metrics

4. **Regional Distribution**:
   - Instance count by region
   - Automated healing events by region

**Access**:
- URL: `http://<grafana-ec2-public-ip>:3000`
- Default credentials: `admin` / `admin` (⚠️ **Change immediately in production**)

---

## Deployment Guide

### Prerequisites

- **AWS Account**: With appropriate permissions
- **Terraform**: Version 1.0+
- **AWS CLI**: Configured with credentials
- **Git**: For version control

### Step 1: Clone the Repository

```bash
git clone <repository-url> auto-heal-infra
cd auto-heal-infra
```

### Step 2: Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
vim terraform.tfvars
```

**Key Variables**:
- `aws_region`: AWS region (e.g., `us-east-1`)
- `environment`: Environment name (e.g., `dev`, `prod`)
- `instance_type`: EC2 instance type
- `monitoring_instance_type`: Type for Nagios/Grafana (e.g., `t3.medium`)
- `alarm_threshold_cpu`: CPU threshold % (e.g., `80`)
- `alarm_threshold_memory`: Memory threshold % (e.g., `85`)
- `alarm_threshold_disk`: Disk threshold % (e.g., `90`)

### Step 3: Initialize Terraform

```bash
terraform init -backend-config="bucket=<your-s3-bucket>" \
               -backend-config="key=auto-heal-infra/terraform.tfstate" \
               -backend-config="region=<your-region>"
```

Or configure backend in `backend/backend.tf` first.

### Step 4: Plan Deployment

```bash
terraform plan -out=tfplan
```

Review the plan for accuracy.

### Step 5: Apply Terraform Configuration

```bash
terraform apply tfplan
```

This will:
- Create VPC and security groups
- Launch EC2 instances (target, Nagios, Grafana)
- Deploy Lambda function
- Create CloudWatch alarms
- Configure SNS topics
- Set up IAM roles and policies

### Step 6: Retrieve Outputs

```bash
terraform output
```

Note the public IPs:
- `nagios_public_ip`: Access Nagios dashboard
- `grafana_public_ip`: Access Grafana dashboard
- `lambda_function_arn`: Lambda function ARN

---

## Post-Deployment Configuration

### Nagios Setup

1. **Access Nagios**:
   ```
   http://<nagios-public-ip>/nagios
   Login: nagiosadmin / nagios
   ```

2. **Change Default Password**:
   ```bash
   ssh -i <key.pem> ec2-user@<nagios-public-ip>
   sudo htpasswd -c /etc/nagios/passwd nagiosadmin
   ```

3. **Add Target EC2 Instances**:
   - Edit `/etc/nagios/objects/localhost.cfg`
   - Define host objects for each target instance
   - Example:
     ```ini
     define host {
         use                 linux-server
         host_name           app-server-1
         address             <target-instance-private-ip>
         hostgroups          production_servers
     }
     ```

4. **Configure Service Checks**:
   - Add HTTP, TCP, or NRPE checks
   - Example:
     ```ini
     define service {
         use                 local-service
         host_name           app-server-1
         service_description HTTP
         check_command       check_http
     }
     ```

5. **Set Up Alert Handlers**:
   - Configure Nagios to send alerts to SNS via custom script or webhook

6. **Restart Nagios**:
   ```bash
   sudo systemctl restart nagios
   ```

### Grafana Setup

1. **Access Grafana**:
   ```
   http://<grafana-public-ip>:3000
   Login: admin / admin
   ```

2. **Change Default Password**:
   - In Grafana UI: Profile → Change Password

3. **Add CloudWatch Data Source**:
   - Configuration → Data Sources → Add
   - Select AWS CloudWatch
   - Configure AWS credentials (IAM role attached to Grafana EC2 will auto-authenticate)
   - Save and test

4. **Import/Create Dashboards**:
   - Use dashboard templates or create custom
   - Add panels for:
     - EC2 instance status
     - CPU/Memory/Disk metrics
     - Lambda invocations and errors
     - SNS message count

5. **Set Up Alerts**:
   - Create alert rules in Grafana
   - Configure notification channels (Email, Slack, PagerDuty)

---

## Project Structure

```
auto-heal-infra/
├── README.md                           # This file
├── DEPLOYMENT_GUIDE.md                 # Detailed deployment instructions
├── PROJECT_CHECKLIST.md                # Project status and milestones
├── SUMMARY.md                          # Quick reference guide
├── requirements.txt                    # Python dependencies
├── quick_start.sh                      # Quick start script
│
├── dashboard/
│   └── cloudwatch_dashboard.json       # CloudWatch dashboard JSON
│
├── lambda/
│   └── auto_heal_lambda.py             # Core Lambda function
│
├── scripts/
│   ├── heal_instance.sh                # Instance-level healing script
│   ├── install_nagios.sh               # Nagios installation script
│   └── install_grafana.sh              # Grafana installation script
│
└── terraform/
    ├── main.tf                         # Main resource definitions
    ├── variables.tf                    # Input variables
    ├── outputs.tf                      # Output values
    ├── providers.tf                    # AWS provider
    ├── monitoring_sg.tf                # Security groups
    ├── nagios_ec2.tf                   # Nagios EC2 setup
    ├── grafana_ec2.tf                  # Grafana EC2 setup
    ├── terraform.tfvars.example        # Example tfvars
    ├── backend/
    │   └── backend.tf                  # Remote state backend
    └── modules/
        ├── ec2_instance/
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── user_data.sh
        ├── lambda_function/
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── iam.tf
        └── sns_topic/
            ├── main.tf
            ├── variables.tf
            └── outputs.tf
```

---

## Accessing Nagios and Grafana

### Nagios Dashboard

**URL**: `http://<nagios-public-ip>/nagios`

**Features**:
- Host and Service status pages
- Alert history
- Performance data graphs
- Configuration verification

**Key Sections**:
- **Hosts**: View all monitored instances
- **Services**: View service status and alerts
- **Alerts**: Historical alert log
- **Graphs**: Performance trending (with Pnp4Nagios or GraphiteWeb)

### Grafana Dashboard

**URL**: `http://<grafana-public-ip>:3000`

**Features**:
- Real-time metric visualization
- Custom dashboard creation
- Alert management
- User and organization management

**Recommended Dashboards**:
1. **Infrastructure Overview**: Instance counts, health status
2. **Performance Metrics**: CPU, Memory, Disk time-series
3. **Healing Activity**: Lambda invocation count, execution time
4. **Regional Analysis**: Instance distribution across regions

---

## Best Practices & Security

### Security Best Practices

1. **IAM Least Privilege**:
   - Lambda role: Only `ec2:DescribeInstances`, `ssm:SendCommand`, `ssm:GetCommandInvocation`
   - Nagios/Grafana roles: Only `ec2:DescribeInstances`, `cloudwatch:GetMetricStatistics`
   - Avoid wildcard (`*`) permissions

2. **Security Groups**:
   - Nagios: Restrict ports 80/443 to your IP/VPN
   - Grafana: Restrict ports 80/443/3000 to your IP/VPN
   - Target instances: Only allow SSM agent traffic

3. **Credentials Management**:
   - Change default Nagios and Grafana passwords immediately
   - Use AWS Secrets Manager for sensitive credentials
   - Enable MFA for AWS console access

4. **Network Isolation**:
   - Deploy in private subnets where possible
   - Use NAT Gateway for outbound traffic
   - Use Security Groups as virtual firewalls

5. **Logging & Auditing**:
   - Enable CloudTrail for AWS API calls
   - Enable VPC Flow Logs for network traffic
   - Centralize logs in CloudWatch Logs or S3

6. **Secrets Management**:
   - Store SNS topics ARNs in Parameter Store
   - Use IAM roles instead of hardcoded credentials
   - Rotate API keys and credentials regularly

### Operational Best Practices

1. **Terraform State**:
   - Use remote state (S3 + DynamoDB for locking)
   - Enable versioning on S3 bucket
   - Restrict access to state files

2. **Lambda Function Updates**:
   - Version and tag Lambda functions
   - Use aliases (`dev`, `prod`)
   - Test updates in dev environment first

3. **Monitoring**:
   - Set up CloudWatch Alarms for Lambda errors
   - Monitor SNS message delivery
   - Track healing action success/failure rates

4. **Scaling**:
   - Use Lambda concurrency limits
   - Configure SNS FIFO for order-guaranteed delivery
   - Implement exponential backoff in Lambda

---

## Troubleshooting

### Lambda Function Not Triggering

1. **Check SNS Topic Subscription**:
   ```bash
   aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
   ```

2. **Check Lambda Permissions**:
   ```bash
   aws lambda get-policy --function-name auto_heal_lambda
   ```

3. **Check CloudWatch Logs**:
   ```bash
   aws logs tail /aws/lambda/auto_heal_lambda --follow
   ```

### SSM Command Execution Failing

1. **Verify SSM Agent on Target Instance**:
   ```bash
   sudo systemctl status amazon-ssm-agent
   ```

2. **Check SSM Document**:
   ```bash
   aws ssm describe-document --name "AWS-RunShellScript"
   ```

3. **Check IAM Role on Target Instance**:
   - Ensure instance has `AmazonSSMManagedInstanceCore` policy

### Nagios Not Detecting Hosts

1. **Verify Host Configuration**:
   ```bash
   sudo /usr/local/nagios/bin/nagios -v /etc/nagios/nagios.cfg
   ```

2. **Check NRPE Service**:
   ```bash
   systemctl status nrpe
   ```

3. **Test NRPE Manually**:
   ```bash
   /usr/local/nagios/libexec/check_nrpe -H <target-ip>
   ```

### Grafana Not Showing Metrics

1. **Verify Data Source**:
   - Configuration → Data Sources → Test
   - Check CloudWatch credentials

2. **Check CloudWatch Agent on Target Instances**:
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
       -a query -m ec2 -c default -s
   ```

3. **Verify IAM Role**:
   - Ensure Grafana EC2 role has `cloudwatch:GetMetricStatistics` permission

---

## Support & Documentation

- **AWS Documentation**: https://docs.aws.amazon.com
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **Nagios Documentation**: https://www.nagios.org/documentation/
- **Grafana Documentation**: https://grafana.com/docs/

---

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]

## Authors

- DevOps Team

---

**Last Updated**: October 2025
