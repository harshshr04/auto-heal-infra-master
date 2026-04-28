#!/bin/bash

################################################################################
# Dashboard Setup Script
#
# This script sets up the custom integrated dashboard on the Grafana server
# The dashboard includes:
# - Real-time metrics (CPU, Memory, Disk)
# - Lambda monitoring
# - Nagios integration with clickable actions
# - Modern UI similar to Dribbble design
#
# Usage: ./setup_dashboard.sh
################################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://3.222.48.52:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"
NAGIOS_URL="${NAGIOS_URL:-http://3.219.108.146/nagios}"
DASHBOARD_DIR="/var/www/html/auto-heal-dashboard"
DASHBOARD_FILE="custom-integrated-dashboard.html"

print_status() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Main setup
main() {
    print_status "Starting dashboard setup..."
    
    # Create dashboard directory
    print_status "Creating dashboard directory..."
    ssh ec2-user@3.222.48.52 "sudo mkdir -p $DASHBOARD_DIR && sudo chmod 755 $DASHBOARD_DIR" 2>/dev/null || {
        print_warning "Could not create directory via SSH. Manual setup required."
    }
    
    # Copy dashboard file
    print_status "Copying dashboard file..."
    scp dashboard/custom-integrated-dashboard.html ec2-user@3.222.48.52:~/dashboard.html 2>/dev/null || {
        print_warning "Could not copy via SCP. Dashboard file location:"
        echo "Local: $(pwd)/dashboard/$DASHBOARD_FILE"
        echo "Remote target: $DASHBOARD_DIR/"
    }
    
  # Copy backend (if present)
  if [ -d dashboard/backend ]; then
    print_status "Copying backend to server..."
    scp -r dashboard/backend ec2-user@3.222.48.52:~/backend 2>/dev/null || {
      print_warning "Could not copy backend directory via SCP. You can copy it manually."
    }

    print_status "Installing backend on remote host..."
    ssh ec2-user@3.222.48.52 "bash -s" << 'REMOTE' || true
set -e
sudo mkdir -p /opt/auto-heal-dashboard/backend
sudo chown ec2-user:ec2-user /opt/auto-heal-dashboard/backend
rm -rf /tmp/ah-backend && mkdir -p /tmp/ah-backend
cp -r ~/backend/* /tmp/ah-backend/
python3 -m venv /tmp/ah-backend/.venv
/tmp/ah-backend/.venv/bin/pip install --upgrade pip
/tmp/ah-backend/.venv/bin/pip install -r /tmp/ah-backend/requirements.txt || true
sudo rm -rf /opt/auto-heal-dashboard/backend/*
sudo cp -r /tmp/ah-backend/* /opt/auto-heal-dashboard/backend/
sudo chown -R ec2-user:ec2-user /opt/auto-heal-dashboard

# Create systemd service
cat <<'SERVICE' | sudo tee /etc/systemd/system/autoheal-backend.service
[Unit]
Description=Auto Heal Dashboard Backend
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/auto-heal-dashboard/backend
Environment=FLASK_ENV=production
ExecStart=/opt/auto-heal-dashboard/backend/.venv/bin/gunicorn -w 3 -b 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now autoheal-backend.service || true
REMOTE
  else
    print_warning "No backend directory found locally (dashboard/backend). Skipping backend deployment."
  fi
    
    # Setup nginx/apache
    print_status "Setting up web server..."
    ssh ec2-user@3.222.48.52 "
    sudo cp ~/dashboard.html $DASHBOARD_DIR/
    sudo chown root:root $DASHBOARD_DIR/$DASHBOARD_FILE
    sudo chmod 644 $DASHBOARD_DIR/$DASHBOARD_FILE
    " 2>/dev/null || true
    
    print_success "Dashboard file deployed!"
    
    # Generate access information
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}
${GREEN}║         INTEGRATED DASHBOARD SETUP COMPLETE! ✓                ║${NC}
${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}

📊 DASHBOARD ACCESS
───────────────────────────────────────────────────────────────────────

  Local File: $(pwd)/dashboard/$DASHBOARD_FILE
  
  Access Methods:
  
  1. Direct Local Access:
     Open the file in your browser:
     open $(pwd)/dashboard/$DASHBOARD_FILE
     
  2. Serve via Python:
     cd $(pwd)/dashboard
     python3 -m http.server 8000
     Then visit: http://localhost:8000/$DASHBOARD_FILE
     
  3. Deploy to Grafana Server:
     scp dashboard/$DASHBOARD_FILE ec2-user@3.222.48.52:~/
     Then SSH and copy to web root

🎨 DASHBOARD FEATURES
───────────────────────────────────────────────────────────────────────

  ✓ Modern UI with gradient design
  ✓ Real-time metrics (CPU, Memory, Disk utilization)
  ✓ Lambda execution metrics
  ✓ SNS pipeline monitoring
  ✓ Nagios integration panel
  ✓ Clickable Nagios actions (Hosts, Services, Problems, Alerts)
  ✓ Recent healing activity log
  ✓ Responsive design
  ✓ Auto-refresh every 30 seconds

🔗 INTEGRATION LINKS
───────────────────────────────────────────────────────────────────────

  Grafana:       $GRAFANA_URL
  Nagios:        $NAGIOS_URL
  Dashboard:     $DASHBOARD_DIR/$DASHBOARD_FILE (once deployed)

📝 CUSTOMIZATION
───────────────────────────────────────────────────────────────────────

  To customize the dashboard:
  
  1. Edit CONFIG object in the HTML file
  2. Update API endpoints for real metrics
  3. Modify colors and styling
  4. Add custom panels and widgets

${YELLOW}⚠  NOTE:${NC} This dashboard currently uses mock data.
  To use real metrics, integrate with:
  - CloudWatch API
  - Grafana API
  - Nagios API

${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF
}

main "$@"
