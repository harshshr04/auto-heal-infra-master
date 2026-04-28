#!/bin/bash

################################################################################
# Grafana Setup Script for Auto-Heal Infrastructure
#
# This script automates the configuration of Grafana with:
# - CloudWatch data source
# - Pre-configured dashboards
# - Alerts and notifications
#
# Usage: ./setup_grafana.sh <grafana_url> <api_token>
# Example: ./setup_grafana.sh http://3.222.48.52:3000 grafana-api-token
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -e

# Configuration
GRAFANA_URL="${1:-http://localhost:3000}"
API_TOKEN="${2:-}"
AWS_REGION="${3:-us-east-1}"
DASHBOARD_FILE="./grafana_dashboard.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $@"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $@"
}

log_error() {
    echo -e "${RED}[✗]${NC} $@"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $@"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    if [ -z "$API_TOKEN" ]; then
        log_warning "API_TOKEN not provided. Using basic auth (admin:admin)"
        log_warning "⚠️  Change Grafana password immediately!"
    fi
    
    log_success "Prerequisites checked"
}

# Test Grafana connectivity
test_grafana() {
    log "Testing Grafana connectivity to $GRAFANA_URL..."
    
    if [ -z "$API_TOKEN" ]; then
        response=$(curl -s -u admin:admin "$GRAFANA_URL/api/health" || echo "")
    else
        response=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$GRAFANA_URL/api/health" || echo "")
    fi
    
    if [[ $response == *"ok"* ]]; then
        log_success "Grafana is accessible"
        return 0
    else
        log_error "Cannot connect to Grafana at $GRAFANA_URL"
        log_error "Response: $response"
        return 1
    fi
}

# Add CloudWatch data source
add_cloudwatch_datasource() {
    log "Adding CloudWatch data source..."
    
    local datasource_payload=$(cat <<EOF
{
  "name": "CloudWatch",
  "type": "cloudwatch",
  "access": "proxy",
  "jsonData": {
    "defaultRegion": "$AWS_REGION",
    "assumeRoleArn": ""
  },
  "isDefault": true
}
EOF
)
    
    if [ -z "$API_TOKEN" ]; then
        response=$(curl -s -X POST \
            -u admin:admin \
            -H "Content-Type: application/json" \
            -d "$datasource_payload" \
            "$GRAFANA_URL/api/datasources")
    else
        response=$(curl -s -X POST \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$datasource_payload" \
            "$GRAFANA_URL/api/datasources")
    fi
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        local datasource_id=$(echo "$response" | jq -r '.id')
        log_success "CloudWatch data source added (ID: $datasource_id)"
        return 0
    else
        if echo "$response" | grep -q "already exists"; then
            log_warning "CloudWatch data source already exists"
            return 0
        else
            log_error "Failed to add CloudWatch data source"
            log_error "Response: $(echo $response | jq .)"
            return 1
        fi
    fi
}

# Import dashboard
import_dashboard() {
    log "Importing Auto-Heal Infrastructure dashboard..."
    
    if [ ! -f "$DASHBOARD_FILE" ]; then
        log_error "Dashboard file not found: $DASHBOARD_FILE"
        return 1
    fi
    
    local dashboard_payload=$(cat <<EOF
{
  "dashboard": $(cat "$DASHBOARD_FILE"),
  "overwrite": true,
  "folderId": 0
}
EOF
)
    
    if [ -z "$API_TOKEN" ]; then
        response=$(curl -s -X POST \
            -u admin:admin \
            -H "Content-Type: application/json" \
            -d "$dashboard_payload" \
            "$GRAFANA_URL/api/dashboards/db")
    else
        response=$(curl -s -X POST \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$dashboard_payload" \
            "$GRAFANA_URL/api/dashboards/db")
    fi
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        local dashboard_url="$GRAFANA_URL/d/$(echo $response | jq -r '.uid')"
        log_success "Dashboard imported successfully"
        echo -e "\n${GREEN}Dashboard URL: $dashboard_url${NC}\n"
        return 0
    else
        log_error "Failed to import dashboard"
        log_error "Response: $(echo $response | jq .)"
        return 1
    fi
}

# Update Grafana settings
update_settings() {
    log "Updating Grafana settings..."
    
    local settings_payload=$(cat <<EOF
{
  "homeDashboardId": 1,
  "timezone": "utc",
  "theme": "dark"
}
EOF
)
    
    if [ -z "$API_TOKEN" ]; then
        curl -s -X PUT \
            -u admin:admin \
            -H "Content-Type: application/json" \
            -d "$settings_payload" \
            "$GRAFANA_URL/api/user/preferences" > /dev/null
    else
        curl -s -X PUT \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$settings_payload" \
            "$GRAFANA_URL/api/user/preferences" > /dev/null
    fi
    
    log_success "Settings updated"
}

# Create notification channel (optional)
create_notification_channel() {
    log "Creating notification channel..."
    
    local channel_payload=$(cat <<EOF
{
  "name": "Auto-Heal Alerts",
  "type": "slack",
  "sendReminder": false,
  "settings": {
    "url": "",
    "mentionUsers": "",
    "mentionGroups": ""
  }
}
EOF
)
    
    log_warning "Slack webhook URL not configured. Skipping notification channel setup."
    log_warning "To add later: Settings → Notification channels"
}

# Generate status report
generate_report() {
    log "Generating setup report..."
    
    cat << EOF

╔════════════════════════════════════════════════════════════════════════════╗
║           ✅ GRAFANA SETUP COMPLETED SUCCESSFULLY ✅                      ║
╚════════════════════════════════════════════════════════════════════════════╝

📊 DASHBOARD CONFIGURATION SUMMARY
────────────────────────────────────────────────────────────────────────────

✓ Grafana URL: $GRAFANA_URL
✓ CloudWatch Data Source: Configured
✓ Auto-Heal Dashboard: Imported
✓ Auto-refresh: 30 seconds

📈 DASHBOARD PANELS
────────────────────────────────────────────────────────────────────────────

1. EC2 CPU Utilization        - Real-time CPU metrics across all instances
2. Memory & Disk Utilization  - Custom CloudWatch metrics
3. Lambda Activity            - Healing function invocations & errors
4. Lambda Duration            - Healing function execution time
5. SNS Alerts                 - Alert notifications published
6. Instance Health Status     - EC2 status check results
7. CloudWatch Alarms          - Alarm trigger counts

🔐 NEXT STEPS
────────────────────────────────────────────────────────────────────────────

1. ✅ Access Grafana:
   URL: $GRAFANA_URL
   Default credentials: admin / admin

2. ✅ CHANGE DEFAULT PASSWORD IMMEDIATELY:
   • Go to Settings → User Profile
   • Click "Change Password"
   • Set a strong password

3. ✅ Configure Slack/Email Notifications (Optional):
   • Settings → Notification channels
   • Add your Slack webhook or email

4. ✅ Customize Dashboard:
   • Edit dashboard to add more panels
   • Set alert thresholds
   • Configure dashboard refresh rate

5. ✅ Monitor Healing Events:
   • Watch Lambda Activity panel
   • Check SNS Alerts panel
   • Monitor instance health status

⚠️  SECURITY REMINDERS
────────────────────────────────────────────────────────────────────────────

✓ Change default Grafana password
✓ Enable HTTPS in production
✓ Restrict network access to Grafana
✓ Enable MFA for admin users
✓ Audit CloudWatch data source permissions

📚 USEFUL LINKS
────────────────────────────────────────────────────────────────────────────

• Grafana Dashboard: $GRAFANA_URL
• CloudWatch Console: https://console.aws.amazon.com/cloudwatch
• Lambda Logs: /aws/lambda/auto-heal-infra-auto-heal
• SNS Topic: auto-heal-alerts

────────────────────────────────────────────────────────────────────────────
Setup completed at: $(date)
────────────────────────────────────────────────────────────────────────────

EOF
}

# Main execution
main() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Grafana Setup for Auto-Heal Infrastructure                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    check_prerequisites
    test_grafana
    add_cloudwatch_datasource
    import_dashboard
    update_settings
    create_notification_channel
    generate_report
}

# Run main
main "$@"
