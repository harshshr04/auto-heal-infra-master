#!/bin/bash

################################################################################
# Target Instance User Data Script
#
# This script is executed when target EC2 instances are launched.
# It sets up CloudWatch agent and installs necessary monitoring tools.
#
# Variables (passed from Terraform):
#   - cloudwatch_namespace: CloudWatch namespace for custom metrics
#   - region: AWS region
#   - instance_number: Instance number for identification
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -e

# Configuration from Terraform
CLOUDWATCH_NAMESPACE="${cloudwatch_namespace}"
AWS_REGION="${region}"
INSTANCE_NUMBER="${instance_number}"
LOG_DIR="/var/log/auto-heal"
LOG_FILE="$LOG_DIR/user_data.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# LOGGING
################################################################################

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $@${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $@${NC}" | tee -a "$LOG_FILE"
}

################################################################################
# SYSTEM SETUP
################################################################################

setup_system() {
    log "Setting up target instance $INSTANCE_NUMBER..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS="unknown"
    fi
    
    log "Detected OS: $OS"
    
    # Update system
    if [ "$OS" = "amzn" ]; then
        log "Updating Amazon Linux system..."
        yum update -y >> "$LOG_FILE" 2>&1
        yum install -y wget curl nmap-ncat net-tools >> "$LOG_FILE" 2>&1
    elif [ "$OS" = "ubuntu" ]; then
        log "Updating Ubuntu system..."
        apt-get update >> "$LOG_FILE" 2>&1
        apt-get upgrade -y >> "$LOG_FILE" 2>&1
        apt-get install -y wget curl netcat net-tools >> "$LOG_FILE" 2>&1
    fi
    
    log_success "System update completed"
}

################################################################################
# SSM AGENT SETUP
################################################################################

setup_ssm_agent() {
    log "Setting up AWS Systems Manager agent..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    if [ "$OS" = "amzn" ]; then
        # Amazon Linux 2 comes with SSM agent pre-installed
        systemctl enable amazon-ssm-agent
        systemctl restart amazon-ssm-agent
        log_success "SSM agent enabled and restarted"
    elif [ "$OS" = "ubuntu" ]; then
        log "Installing SSM agent on Ubuntu..."
        snap install amazon-ssm-agent --classic >> "$LOG_FILE" 2>&1
        snap start amazon-ssm-agent >> "$LOG_FILE" 2>&1
        log_success "SSM agent installed and started"
    fi
}

################################################################################
# CLOUDWATCH AGENT INSTALLATION
################################################################################

install_cloudwatch_agent() {
    log "Installing CloudWatch agent..."
    
    cd /tmp
    
    # Detect OS and download appropriate agent
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    if [ "$OS" = "amzn" ]; then
        log "Downloading CloudWatch agent for Amazon Linux..."
        wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
        rpm -U ./amazon-cloudwatch-agent.rpm >> "$LOG_FILE" 2>&1
    elif [ "$OS" = "ubuntu" ]; then
        log "Downloading CloudWatch agent for Ubuntu..."
        wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
        dpkg -i -E ./amazon-cloudwatch-agent.deb >> "$LOG_FILE" 2>&1
    fi
    
    log_success "CloudWatch agent installed"
}

################################################################################
# CLOUDWATCH AGENT CONFIGURATION
################################################################################

configure_cloudwatch_agent() {
    log "Configuring CloudWatch agent..."
    
    local agent_config="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    
    # Create CloudWatch agent configuration
    cat > "$agent_config" << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/target-instance-${INSTANCE_NUMBER}",
            "log_stream_name": "/var/log/messages"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/aws/ec2/target-instance-${INSTANCE_NUMBER}",
            "log_stream_name": "/var/log/secure"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "${CLOUDWATCH_NAMESPACE}",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_USAGE_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "rename": "CPU_USAGE_IOWAIT",
            "unit": "Percent"
          },
          "cpu_time_guest"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DiskUtilization",
            "unit": "Percent"
          },
          {
            "name": "free",
            "rename": "DiskFree",
            "unit": "Gigabytes"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "/"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MemoryUtilization",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "rename": "TCPEstablished",
            "unit": "Count"
          },
          {
            "name": "tcp_time_wait",
            "rename": "TCPTimeWait",
            "unit": "Count"
          }
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

    log_success "CloudWatch agent configured"
}

################################################################################
# START CLOUDWATCH AGENT
################################################################################

start_cloudwatch_agent() {
    log "Starting CloudWatch agent..."
    
    # Start the agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a query -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s \
        >> "$LOG_FILE" 2>&1
    
    # Verify it's running
    sleep 5
    if /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a query -m ec2 | grep -q "running"; then
        log_success "CloudWatch agent started successfully"
    else
        log_error "CloudWatch agent failed to start"
    fi
}

################################################################################
# INSTALL MONITORING TOOLS
################################################################################

install_monitoring_tools() {
    log "Installing monitoring and diagnostic tools..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    if [ "$OS" = "amzn" ]; then
        yum install -y \
            sysstat htop iotop iftop \
            strace ltrace \
            telnet netstat \
            >> "$LOG_FILE" 2>&1
    elif [ "$OS" = "ubuntu" ]; then
        apt-get install -y \
            sysstat htop iotop iftop \
            strace ltrace \
            telnet >> "$LOG_FILE" 2>&1
    fi
    
    log_success "Monitoring tools installed"
}

################################################################################
# SETUP NRPE AGENT (for Nagios)
################################################################################

setup_nrpe_agent() {
    log "Setting up NRPE agent for Nagios..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    if [ "$OS" = "amzn" ]; then
        yum install -y nrpe nagios-plugins-all >> "$LOG_FILE" 2>&1
        
        # Start NRPE service
        systemctl enable nrpe
        systemctl start nrpe
    elif [ "$OS" = "ubuntu" ]; then
        apt-get install -y nagios-nrpe-server nagios-plugins >> "$LOG_FILE" 2>&1
        
        # Start NRPE service
        systemctl enable nagios-nrpe-server
        systemctl start nagios-nrpe-server
    fi
    
    log_success "NRPE agent configured"
}

################################################################################
# INSTALL DEMO APPLICATION
################################################################################

install_demo_application() {
    log "Installing demo web application..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    if [ "$OS" = "amzn" ]; then
        yum install -y httpd >> "$LOG_FILE" 2>&1
        
        # Enable and start
        systemctl enable httpd
        systemctl start httpd
        
        # Create demo page
        cat > /var/www/html/index.html << 'DEMO_HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Auto-Heal Infrastructure - Demo App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #4CAF50; color: white; padding: 20px; border-radius: 5px; }
        .info { background-color: #f0f0f0; padding: 15px; margin: 20px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Auto-Heal Infrastructure Demo Application</h1>
    </div>
    <div class="info">
        <h2>Instance Information</h2>
        <p><strong>Instance ID:</strong> <code id="instance-id">Loading...</code></p>
        <p><strong>Availability Zone:</strong> <code id="availability-zone">Loading...</code></p>
        <p><strong>Timestamp:</strong> <code id="timestamp">Loading...</code></p>
    </div>
    <script>
        // Try to fetch instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(r => r.text())
            .then(id => document.getElementById('instance-id').innerHTML = id);
        
        fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            .then(r => r.text())
            .then(az => document.getElementById('availability-zone').innerHTML = az);
        
        document.getElementById('timestamp').innerHTML = new Date().toISOString();
    </script>
</body>
</html>
DEMO_HTML
    
    elif [ "$OS" = "ubuntu" ]; then
        apt-get install -y apache2 >> "$LOG_FILE" 2>&1
        
        # Enable and start
        systemctl enable apache2
        systemctl start apache2
        
        # Create demo page
        cat > /var/www/html/index.html << 'DEMO_HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Auto-Heal Infrastructure - Demo App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #4CAF50; color: white; padding: 20px; border-radius: 5px; }
        .info { background-color: #f0f0f0; padding: 15px; margin: 20px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Auto-Heal Infrastructure Demo Application</h1>
    </div>
    <div class="info">
        <h2>Instance Information</h2>
        <p><strong>Instance ID:</strong> <code id="instance-id">Loading...</code></p>
        <p><strong>Availability Zone:</strong> <code id="availability-zone">Loading...</code></p>
        <p><strong>Timestamp:</strong> <code id="timestamp">Loading...</code></p>
    </div>
    <script>
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(r => r.text())
            .then(id => document.getElementById('instance-id').innerHTML = id);
        
        fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            .then(r => r.text())
            .then(az => document.getElementById('availability-zone').innerHTML = az);
        
        document.getElementById('timestamp').innerHTML = new Date().toISOString();
    </script>
</body>
</html>
DEMO_HTML
    fi
    
    log_success "Demo application installed"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log "=========================================="
    log "Target Instance Setup Started"
    log "Instance Number: $INSTANCE_NUMBER"
    log "CloudWatch Namespace: $CLOUDWATCH_NAMESPACE"
    log "AWS Region: $AWS_REGION"
    log "Timestamp: $(date)"
    log "=========================================="
    
    # Run setup steps
    setup_system
    setup_ssm_agent
    install_cloudwatch_agent
    configure_cloudwatch_agent
    start_cloudwatch_agent
    install_monitoring_tools
    setup_nrpe_agent
    install_demo_application
    
    log "=========================================="
    log_success "Target Instance Setup Completed!"
    log "=========================================="
    log ""
    log "Setup Details:"
    log "- SSM Agent: Ready for remote command execution"
    log "- CloudWatch Agent: Collecting metrics to $CLOUDWATCH_NAMESPACE"
    log "- Nagios NRPE: Ready for remote monitoring checks"
    log "- Demo Application: Running on port 80"
    log ""
    log "Log file: $LOG_FILE"
    log "=========================================="
}

# Run main function
main "$@"
