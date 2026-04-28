#!/bin/bash

################################################################################
# Grafana Installation Script for Auto-Heal Infrastructure
#
# This script installs and configures Grafana on Amazon Linux 2 or Ubuntu
# as part of EC2 user data. It sets up dashboards and data sources for
# visualizing Auto-Heal Infrastructure metrics.
#
# Supported OS:
#   - Amazon Linux 2
#   - Ubuntu 18.04+
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -e  # Exit on error

# Configuration
GRAFANA_VERSION="10.3.3"
GRAFANA_HOME="/usr/share/grafana"
GRAFANA_DATA="/var/lib/grafana"
GRAFANA_CONFIG="/etc/grafana"
GRAFANA_USER="grafana"
GRAFANA_GROUP="grafana"
GRAFANA_PORT="3000"
LOG_FILE="/var/log/grafana-install.log"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# LOGGING
################################################################################

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
# SYSTEM PREPARATION
################################################################################

prepare_system() {
    log "Preparing system..."
    
    if [ "$OS" = "amzn" ]; then
        log "Detected Amazon Linux 2"
        
        # Update system
        log "Updating system packages..."
        yum update -y >> "$LOG_FILE" 2>&1
        
        # Install dependencies
        log "Installing dependencies..."
        yum install -y \
            wget curl tar gzip fontconfig freetype \
            initscripts >> "$LOG_FILE" 2>&1
        
    elif [ "$OS" = "ubuntu" ]; then
        log "Detected Ubuntu"
        
        # Update system
        log "Updating system packages..."
        apt-get update >> "$LOG_FILE" 2>&1
        apt-get upgrade -y >> "$LOG_FILE" 2>&1
        
        # Install dependencies
        log "Installing dependencies..."
        apt-get install -y \
            wget curl apt-transport-https software-properties-common \
            adduser libfontconfig1 musl >> "$LOG_FILE" 2>&1
    else
        log_error "Unsupported OS: $OS"
        exit 1
    fi
    
    log_success "System preparation completed"
}

################################################################################
# GRAFANA INSTALLATION
################################################################################

install_grafana() {
    log "Installing Grafana v$GRAFANA_VERSION..."
    
    if [ "$OS" = "amzn" ]; then
        log "Adding Grafana repository for Amazon Linux..."
        cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

        log "Installing Grafana via yum..."
        yum install -y grafana >> "$LOG_FILE" 2>&1
        
    elif [ "$OS" = "ubuntu" ]; then
        log "Adding Grafana repository for Ubuntu..."
        apt-get install -y software-properties-common >> "$LOG_FILE" 2>&1
        add-apt-repository "deb https://packages.grafana.com/oss/deb stable main" >> "$LOG_FILE" 2>&1
        apt-get update >> "$LOG_FILE" 2>&1
        
        log "Installing Grafana via apt..."
        apt-get install -y grafana >> "$LOG_FILE" 2>&1
    fi
    
    log_success "Grafana installation completed"
}

################################################################################
# GRAFANA CONFIGURATION
################################################################################

configure_grafana() {
    log "Configuring Grafana..."
    
    # Ensure Grafana config directory exists
    mkdir -p "$GRAFANA_CONFIG"
    mkdir -p "$GRAFANA_DATA"
    mkdir -p "$GRAFANA_CONFIG/provisioning/datasources"
    mkdir -p "$GRAFANA_CONFIG/provisioning/dashboards"
    
    # Create provisioning directory for datasources
    cat > "$GRAFANA_CONFIG/provisioning/datasources/cloudwatch.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: CloudWatch
    type: cloudwatch
    access: proxy
    isDefault: true
    version: 1
    editable: true
    jsonData:
      defaultRegion: us-east-1
      assumeRoleEnabled: false
EOF

    # Create provisioning directory for dashboards
    mkdir -p "$GRAFANA_DATA/dashboards"
    
    cat > "$GRAFANA_CONFIG/provisioning/dashboards/auto-heal.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'Auto-Heal Dashboards'
    orgId: 1
    folder: 'Auto-Heal'
    type: file
    disableDeletion: false
    editable: true
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Set permissions
    chown -R grafana:grafana "$GRAFANA_CONFIG"
    chown -R grafana:grafana "$GRAFANA_DATA"
    
    log_success "Grafana configuration completed"
}

################################################################################
# GRAFANA DASHBOARDS
################################################################################

create_dashboards() {
    log "Creating Grafana dashboards..."
    
    # Infrastructure Overview Dashboard
    cat > "$GRAFANA_DATA/dashboards/infrastructure-overview.json" << 'EOF'
{
  "dashboard": {
    "title": "Auto-Heal Infrastructure Overview",
    "tags": ["auto-heal", "infrastructure"],
    "timezone": "browser",
    "panels": [
      {
        "type": "graph",
        "title": "EC2 CPU Utilization",
        "targets": [
          {
            "alias": "{{ instance_id }}",
            "dimensions": {
              "InstanceId": "all"
            },
            "expression": "",
            "id": "",
            "matchExact": true,
            "metricName": "CPUUtilization",
            "namespace": "AWS/EC2",
            "period": "300",
            "refId": "A",
            "statistics": ["Average"]
          }
        ],
        "yaxes": [
          {
            "format": "percent",
            "label": "CPU %",
            "logBase": 1,
            "max": 100,
            "min": 0,
            "show": true
          }
        ]
      },
      {
        "type": "graph",
        "title": "Instance Status Checks",
        "targets": [
          {
            "dimensions": {
              "InstanceId": "all"
            },
            "metricName": "StatusCheckFailed",
            "namespace": "AWS/EC2",
            "period": "300",
            "refId": "A",
            "statistics": ["Maximum"]
          }
        ]
      },
      {
        "type": "stat",
        "title": "Running Instances",
        "targets": [
          {
            "dimensions": {
              "InstanceId": "all"
            },
            "metricName": "RunningInstanceCount",
            "namespace": "AWS/EC2",
            "period": "300",
            "refId": "A",
            "statistics": ["Average"]
          }
        ]
      }
    ],
    "version": 1,
    "schemaVersion": 27,
    "style": "dark",
    "refresh": "30s"
  },
  "overwrite": true
}
EOF

    # Lambda Healing Activity Dashboard
    cat > "$GRAFANA_DATA/dashboards/healing-activity.json" << 'EOF'
{
  "dashboard": {
    "title": "Auto-Heal Activity",
    "tags": ["auto-heal", "healing", "lambda"],
    "timezone": "browser",
    "panels": [
      {
        "type": "graph",
        "title": "Lambda Invocations",
        "targets": [
          {
            "dimensions": {
              "FunctionName": "auto_heal_lambda"
            },
            "metricName": "Invocations",
            "namespace": "AWS/Lambda",
            "period": "300",
            "refId": "A",
            "statistics": ["Sum"]
          }
        ],
        "yaxes": [
          {
            "format": "short",
            "label": "Count",
            "logBase": 1,
            "show": true
          }
        ]
      },
      {
        "type": "graph",
        "title": "Lambda Execution Duration",
        "targets": [
          {
            "dimensions": {
              "FunctionName": "auto_heal_lambda"
            },
            "metricName": "Duration",
            "namespace": "AWS/Lambda",
            "period": "300",
            "refId": "A",
            "statistics": ["Average", "Maximum"]
          }
        ],
        "yaxes": [
          {
            "format": "ms",
            "label": "Duration (ms)",
            "logBase": 1,
            "show": true
          }
        ]
      },
      {
        "type": "graph",
        "title": "Lambda Errors",
        "targets": [
          {
            "dimensions": {
              "FunctionName": "auto_heal_lambda"
            },
            "metricName": "Errors",
            "namespace": "AWS/Lambda",
            "period": "300",
            "refId": "A",
            "statistics": ["Sum"]
          }
        ],
        "yaxes": [
          {
            "format": "short",
            "label": "Count",
            "logBase": 1,
            "show": true
          }
        ]
      },
      {
        "type": "graph",
        "title": "SNS Messages Published",
        "targets": [
          {
            "dimensions": {
              "TopicName": "auto-heal-alerts"
            },
            "metricName": "NumberOfMessagesPublished",
            "namespace": "AWS/SNS",
            "period": "300",
            "refId": "A",
            "statistics": ["Sum"]
          }
        ]
      }
    ],
    "version": 1,
    "schemaVersion": 27,
    "style": "dark",
    "refresh": "30s"
  },
  "overwrite": true
}
EOF

    chown grafana:grafana "$GRAFANA_DATA/dashboards"/*.json
    
    log_success "Dashboards created"
}

################################################################################
# SERVICE CONFIGURATION
################################################################################

setup_services() {
    log "Setting up Grafana service..."
    
    # Enable and start Grafana
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl restart grafana-server
    
    # Wait for Grafana to start
    log "Waiting for Grafana to start..."
    sleep 5
    
    # Check if Grafana is running
    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana service started successfully"
    else
        log_error "Grafana service failed to start"
        systemctl status grafana-server >> "$LOG_FILE" 2>&1
    fi
}

################################################################################
# FIREWALL CONFIGURATION
################################################################################

setup_firewall() {
    log "Configuring firewall for Grafana port $GRAFANA_PORT..."
    
    if [ "$OS" = "amzn" ]; then
        # Amazon Linux uses firewalld or iptables
        if command -v firewall-cmd &> /dev/null; then
            firewall-cmd --permanent --add-port=$GRAFANA_PORT/tcp
            firewall-cmd --reload 2>/dev/null || true
            log_success "Firewalld rule added"
        fi
    else
        # Ubuntu uses UFW or iptables
        if command -v ufw &> /dev/null; then
            ufw allow $GRAFANA_PORT/tcp
            log_success "UFW rule added"
        fi
    fi
}

################################################################################
# GRAFANA INITIALIZATION
################################################################################

initialize_grafana() {
    log "Initializing Grafana..."
    
    # Wait for Grafana to be ready
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:$GRAFANA_PORT/api/health >/dev/null 2>&1; then
            log_success "Grafana is ready"
            
            # Update admin password via API
            log "Updating admin password..."
            curl -s -X POST -H "Content-Type: application/json" \
                --data-raw '{"password":"admin"}' \
                -u admin:admin \
                http://localhost:$GRAFANA_PORT/api/user/password >> "$LOG_FILE" 2>&1 || true
            
            return 0
        fi
        
        log "Waiting for Grafana to be ready... (attempt $((attempt + 1))/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    log_error "Grafana failed to start within timeout"
    return 1
}

################################################################################
# CLOUDWATCH AGENT SETUP
################################################################################

setup_cloudwatch() {
    log "Setting up CloudWatch integration..."
    
    # Install CloudWatch agent
    cd /tmp
    if [ "$OS" = "amzn" ]; then
        wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
        rpm -U ./amazon-cloudwatch-agent.rpm >> "$LOG_FILE" 2>&1
    else
        wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
        dpkg -i -E ./amazon-cloudwatch-agent.deb >> "$LOG_FILE" 2>&1
    fi
    
    log_success "CloudWatch agent installed"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log "=========================================="
    log "Grafana Installation Started"
    log "OS: $OS"
    log "Timestamp: $(date)"
    log "=========================================="
    
    # Run installation steps
    prepare_system
    install_grafana
    configure_grafana
    create_dashboards
    setup_services
    setup_firewall
    setup_cloudwatch
    initialize_grafana
    
    log "=========================================="
    log_success "Grafana Installation Completed!"
    log "=========================================="
    log ""
    log "Access Grafana at: http://$(hostname -I | awk '{print $1}'):$GRAFANA_PORT"
    log "Username: admin"
    log "Password: admin"
    log ""
    log "⚠️  IMPORTANT: Change the default password immediately!"
    log ""
    log "Next Steps:"
    log "1. Login to Grafana at the URL above"
    log "2. Go to Configuration → Data Sources"
    log "3. Add CloudWatch data source with your AWS region"
    log "4. Import auto-heal dashboards from the dashboards section"
    log ""
    log "Configuration directory: $GRAFANA_CONFIG"
    log "Data directory: $GRAFANA_DATA"
    log "Log file: $LOG_FILE"
    log "Dashboards: $GRAFANA_DATA/dashboards"
    log "=========================================="
}

# Run main function
main "$@"
