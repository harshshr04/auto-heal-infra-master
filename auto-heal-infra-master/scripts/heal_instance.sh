#!/bin/bash

################################################################################
# Healing Script for Auto-Heal Infrastructure
#
# This script is executed on target EC2 instances via AWS Systems Manager (SSM)
# to perform instance-level remediation and healing actions.
#
# Usage: ./heal_instance.sh [action] [parameter]
#
# Supported Actions:
#   - restart_service [service_name]
#   - clear_cache
#   - cleanup_logs
#   - disk_cleanup
#   - optimize_performance
#   - restart_all_services
#   - full_diagnostic
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -o pipefail

# Configuration
SCRIPT_NAME=$(basename "$0")
LOG_DIR="/var/log/auto-heal"
LOG_FILE="${LOG_DIR}/healing-$(date +%Y%m%d_%H%M%S).log"
LOCK_FILE="/var/run/auto-heal.lock"
LOCK_TIMEOUT=600  # 10 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

################################################################################
# LOGGING & UTILITY FUNCTIONS
################################################################################

# Create log directory
mkdir -p "$LOG_DIR"

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

# Acquire lock to prevent concurrent executions
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_age=$(($(date +%s) - $(stat -f%m "$LOCK_FILE" 2>/dev/null || stat -c%Y "$LOCK_FILE")))
        if [ $lock_age -lt $LOCK_TIMEOUT ]; then
            log_error "Healing already in progress (lock acquired $(${lock_age}s ago)"
            return 1
        else
            log_warn "Removing stale lock file (older than ${LOCK_TIMEOUT}s)"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    touch "$LOCK_FILE"
    return 0
}

# Release lock
release_lock() {
    rm -f "$LOCK_FILE"
}

# Report metrics
report_metrics() {
    local metric_name="$1"
    local metric_value="$2"
    local metric_unit="${3:-None}"
    
    # Push custom metric to CloudWatch (optional)
    aws cloudwatch put-metric-data \
        --namespace "auto-heal-infra" \
        --metric-name "$metric_name" \
        --value "$metric_value" \
        --unit "$metric_unit" 2>/dev/null || true
}

################################################################################
# HEALING ACTIONS
################################################################################

# Restart a specific service
restart_service() {
    local service_name="$1"
    
    if [ -z "$service_name" ]; then
        log_error "Service name required"
        return 1
    fi
    
    log_info "Attempting to restart service: $service_name"
    
    # Try systemctl first (modern systems)
    if command -v systemctl &> /dev/null; then
        log_info "Using systemctl to restart $service_name"
        if systemctl is-active --quiet "$service_name"; then
            systemctl restart "$service_name"
            if [ $? -eq 0 ]; then
                log_success "Successfully restarted $service_name via systemctl"
                return 0
            else
                log_error "Failed to restart $service_name via systemctl"
                return 1
            fi
        else
            log_warn "Service $service_name not active, attempting to start"
            systemctl start "$service_name"
            [ $? -eq 0 ] && log_success "Started $service_name" || log_error "Failed to start $service_name"
        fi
    fi
    
    # Fallback to service command
    if command -v service &> /dev/null; then
        log_info "Using service command to restart $service_name"
        service "$service_name" restart
        if [ $? -eq 0 ]; then
            log_success "Successfully restarted $service_name via service"
            return 0
        else
            log_error "Failed to restart $service_name via service"
            return 1
        fi
    fi
    
    log_error "No service manager found (systemctl or service)"
    return 1
}

# Clear system caches
clear_cache() {
    log_info "Starting cache clearing..."
    
    # Sync filesystem first
    log_info "Syncing filesystem..."
    sync
    
    # Clear page cache (requires root)
    if [ "$(id -u)" -eq 0 ]; then
        log_info "Clearing page cache..."
        echo 3 > /proc/sys/vm/drop_caches
        [ $? -eq 0 ] && log_success "Page cache cleared" || log_warn "Failed to clear page cache"
        
        # Clear inode and dentry cache
        log_info "Clearing inode and dentry cache..."
        sync
        echo 2 > /proc/sys/vm/drop_caches
        [ $? -eq 0 ] && log_success "Inode and dentry cache cleared"
    else
        log_warn "Not running as root, skipping page cache clearing"
    fi
    
    # Clear package manager caches
    if command -v yum &> /dev/null; then
        log_info "Clearing yum cache..."
        yum clean all >/dev/null 2>&1
        [ $? -eq 0 ] && log_success "Yum cache cleared"
    fi
    
    if command -v apt-get &> /dev/null; then
        log_info "Clearing apt cache..."
        apt-get clean >/dev/null 2>&1
        [ $? -eq 0 ] && log_success "Apt cache cleared"
    fi
    
    # Get current memory usage
    local mem_before=$(free | grep Mem | awk '{print $3}')
    log_info "Current memory usage: ${mem_before}KB"
    report_metrics "MemoryFreed" "$((mem_before / 1024))" "Megabytes"
    
    log_success "Cache clearing completed"
    return 0
}

# Cleanup old log files
cleanup_logs() {
    log_info "Starting log cleanup..."
    
    local days_old="${1:-7}"  # Default to 7 days
    
    log_info "Removing log files older than $days_old days..."
    find /var/log -type f -name "*.log" -mtime "+${days_old}" -delete 2>/dev/null
    local deleted_count=$?
    
    if [ $deleted_count -eq 0 ]; then
        log_success "Successfully cleaned up log files"
    else
        log_warn "Log cleanup completed with exit code: $deleted_count"
    fi
    
    # Compress recent logs
    log_info "Compressing recent logs..."
    find /var/log -type f -name "*.log" -mtime "-${days_old}" -size "+100M" ! -name "*.gz" \
        -exec gzip {} \; 2>/dev/null
    [ $? -eq 0 ] && log_success "Log compression completed"
    
    # Get freed space
    local freed_space=$(du -sh /var/log | awk '{print $1}')
    log_info "Log directory size: $freed_space"
    report_metrics "LogDirectorySizeGB" "${freed_space%G*}" "Gigabytes"
    
    return 0
}

# Cleanup disk space
disk_cleanup() {
    log_info "Starting disk cleanup..."
    
    # Get initial disk usage
    local initial_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    log_info "Initial disk usage: ${initial_usage}%"
    
    # Clear temporary files
    log_info "Removing temporary files..."
    rm -rf /tmp/* 2>/dev/null
    [ $? -eq 0 ] && log_success "Temporary files cleaned"
    
    rm -rf /var/tmp/* 2>/dev/null
    [ $? -eq 0 ] && log_success "Variable temporary files cleaned"
    
    # Clear package manager cache
    if command -v yum &> /dev/null; then
        yum clean all >/dev/null 2>&1
        log_success "Yum cache cleared"
    fi
    
    if command -v apt-get &> /dev/null; then
        apt-get autoclean >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        log_success "Apt cache and packages cleaned"
    fi
    
    # Remove journal files older than 1 week
    if command -v journalctl &> /dev/null; then
        log_info "Cleaning journalctl logs..."
        journalctl --vacuum=1w >/dev/null 2>&1
        [ $? -eq 0 ] && log_success "Journal cleaned"
    fi
    
    # Get final disk usage
    local final_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    local freed_percent=$((initial_usage - final_usage))
    log_success "Disk cleanup completed. Freed ${freed_percent}% disk space"
    report_metrics "DiskSpaceFreed" "$freed_percent" "Percent"
    
    return 0
}

# Optimize system performance
optimize_performance() {
    log_info "Starting performance optimization..."
    
    # Kill runaway processes
    log_info "Checking for runaway processes..."
    local high_cpu_processes=$(ps aux --sort=-%cpu | head -n 5 | tail -n 4)
    log_info "High CPU processes:\n$high_cpu_processes"
    
    # Check for zombie processes
    local zombie_count=$(ps aux | grep -c " <defunct>")
    if [ "$zombie_count" -gt 0 ]; then
        log_warn "Found $zombie_count zombie processes"
        # Try to clean them up
        pkill -9 -f "" 2>/dev/null || true
    fi
    
    # Optimize network buffers (if applicable)
    if [ "$(id -u)" -eq 0 ]; then
        log_info "Optimizing network buffers..."
        sysctl -q -w net.core.rmem_max=134217728
        sysctl -q -w net.core.wmem_max=134217728
        [ $? -eq 0 ] && log_success "Network buffers optimized"
    fi
    
    # Optimize I/O scheduler
    log_info "Optimizing I/O scheduler..."
    for disk in /sys/block/*/queue/scheduler; do
        if [ -w "$disk" ]; then
            echo "noop" > "$disk" 2>/dev/null || echo "none" > "$disk" 2>/dev/null
        fi
    done
    
    # Run full diagnostic
    full_diagnostic
    
    log_success "Performance optimization completed"
    return 0
}

# Restart all common services
restart_all_services() {
    log_info "Restarting all common services..."
    
    local services=("httpd" "nginx" "mysql" "mariadb" "postgresql" "redis" "memcached")
    local restarted=0
    local failed=0
    
    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_info "Attempting to restart $service..."
            if systemctl restart "$service" 2>/dev/null; then
                log_success "Restarted $service"
                ((restarted++))
            else
                log_warn "Failed to restart $service"
                ((failed++))
            fi
        fi
    done
    
    log_success "Service restart completed: $restarted succeeded, $failed failed"
    return 0
}

# Full system diagnostic
full_diagnostic() {
    log_info "Running full system diagnostic..."
    
    # System uptime
    log_info "System uptime:"
    uptime | tee -a "$LOG_FILE"
    
    # Disk space
    log_info "Disk space:"
    df -h | tee -a "$LOG_FILE"
    
    # Memory usage
    log_info "Memory usage:"
    free -m | tee -a "$LOG_FILE"
    
    # CPU info
    log_info "CPU load average:"
    cat /proc/loadavg | tee -a "$LOG_FILE"
    
    # Top CPU processes
    log_info "Top CPU processes:"
    ps aux --sort=-%cpu | head -n 11 | tee -a "$LOG_FILE"
    
    # Top memory processes
    log_info "Top memory processes:"
    ps aux --sort=-%mem | head -n 11 | tee -a "$LOG_FILE"
    
    # Network interfaces
    log_info "Network interfaces:"
    ip addr 2>/dev/null || ifconfig 2>/dev/null | tee -a "$LOG_FILE"
    
    # Active connections
    log_info "Active network connections:"
    netstat -tan | tail -1 | tee -a "$LOG_FILE" || ss -tan | tail -1 | tee -a "$LOG_FILE"
    
    log_success "Full diagnostic completed"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    local action="${1:-diagnostic}"
    local parameter="${2:-}"
    
    log_info "Auto-Heal Script Started"
    log_info "Action: $action"
    
    # Acquire lock
    if ! acquire_lock; then
        log_error "Failed to acquire lock"
        return 1
    fi
    
    # Execute action
    case "$action" in
        restart_service)
            restart_service "$parameter"
            ;;
        clear_cache)
            clear_cache
            ;;
        cleanup_logs)
            cleanup_logs "$parameter"
            ;;
        disk_cleanup)
            disk_cleanup
            ;;
        optimize_performance|optimize)
            optimize_performance
            ;;
        restart_all)
            restart_all_services
            ;;
        diagnostic|diag|full_diagnostic)
            full_diagnostic
            ;;
        *)
            log_error "Unknown action: $action"
            log_info "Available actions: restart_service, clear_cache, cleanup_logs, disk_cleanup, optimize_performance, restart_all, diagnostic"
            release_lock
            return 1
            ;;
    esac
    
    local exit_code=$?
    
    # Release lock
    release_lock
    
    log_info "Auto-Heal Script Completed (exit code: $exit_code)"
    return $exit_code
}

# Run main function
main "$@"
