#!/bin/bash

################################################################################
# Nagios Core Installation Script for Auto-Heal Infrastructure
#
# This script installs and configures Nagios Core on Amazon Linux 2 or Ubuntu
# as part of EC2 user data. It sets up monitoring for target instances.
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
NAGIOS_VERSION="4.4.11"
NAGIOS_PLUGINS_VERSION="2.4.3"
NRPE_VERSION="4.1.1"
NAGIOS_USER="nagios"
NAGIOS_GROUP="nagios"
NAGIOS_HOME="/usr/local/nagios"
NAGIOS_WEB_HOME="/usr/share/nagios"
APACHE_USER="apache"
LOG_FILE="/var/log/nagios-install.log"

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
            wget unzip make gcc glibc glibc-common autoconf automake libtool \
            apache2-devel openssl-devel perl-devel libgd-devel base64 \
            gd gd-devel net-snmp net-snmp-utils net-snmp-libs \
            httpd mod_ssl php php-gd >> "$LOG_FILE" 2>&1
        
        APACHE_USER="apache"
        
    elif [ "$OS" = "ubuntu" ]; then
        log "Detected Ubuntu"
        
        # Update system
        log "Updating system packages..."
        apt-get update >> "$LOG_FILE" 2>&1
        apt-get upgrade -y >> "$LOG_FILE" 2>&1
        
        # Install dependencies
        log "Installing dependencies..."
        apt-get install -y \
            wget unzip build-essential libssl-dev libc6 libmcrypt-dev \
            make gcc apache2-dev apache2 libapache2-mod-php \
            libgd-dev libpng-dev zlib1g-dev libsnmp-dev snmp snmp-mibs-downloader \
            gettext php php-gd >> "$LOG_FILE" 2>&1
        
        APACHE_USER="www-data"
    else
        log_error "Unsupported OS: $OS"
        exit 1
    fi
    
    log_success "System preparation completed"
}

################################################################################
# NAGIOS USER AND GROUP
################################################################################

setup_users_groups() {
    log "Setting up Nagios user and group..."
    
    # Create nagios user
    if ! id "$NAGIOS_USER" &>/dev/null; then
        useradd --system --home-dir "$NAGIOS_HOME" --shell /bin/bash "$NAGIOS_USER"
        log_success "Created $NAGIOS_USER user"
    else
        log "User $NAGIOS_USER already exists"
    fi
    
    # Create nagios group and add users
    if ! getent group "$NAGIOS_GROUP" >/dev/null; then
        groupadd --system "$NAGIOS_GROUP"
        log_success "Created $NAGIOS_GROUP group"
    fi
    
    # Add nagios user to group
    usermod -a -G "$NAGIOS_GROUP" "$NAGIOS_USER"
    
    # Add apache to nagios group
    usermod -a -G "$NAGIOS_GROUP" "$APACHE_USER"
    
    log_success "User and group setup completed"
}

################################################################################
# NAGIOS CORE INSTALLATION
################################################################################

install_nagios_core() {
    log "Installing Nagios Core v$NAGIOS_VERSION..."
    
    cd /tmp
    
    # Download Nagios Core
    log "Downloading Nagios Core..."
    wget -q "https://assets.nagios.com/downloads/nagioscore/releases/nagios-${NAGIOS_VERSION}.tar.gz"
    tar xzf "nagios-${NAGIOS_VERSION}.tar.gz"
    cd "nagios-${NAGIOS_VERSION}"
    
    # Configure
    log "Configuring Nagios Core..."
    ./configure \
        --prefix="$NAGIOS_HOME" \
        --exec-prefix="$NAGIOS_HOME" \
        --libexecdir="$NAGIOS_HOME/libexec" \
        --sysconfdir="$NAGIOS_HOME/etc" \
        --localstatedir="$NAGIOS_HOME/var" \
        --with-nagios-user="$NAGIOS_USER" \
        --with-nagios-group="$NAGIOS_GROUP" \
        >> "$LOG_FILE" 2>&1
    
    # Compile and install
    log "Compiling and installing..."
    make all >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1
    make install-init >> "$LOG_FILE" 2>&1
    make install-config >> "$LOG_FILE" 2>&1
    make install-webconf >> "$LOG_FILE" 2>&1
    
    log_success "Nagios Core installation completed"
}

################################################################################
# NAGIOS PLUGINS INSTALLATION
################################################################################

install_nagios_plugins() {
    log "Installing Nagios Plugins v$NAGIOS_PLUGINS_VERSION..."
    
    cd /tmp
    
    # Download plugins
    log "Downloading Nagios Plugins..."
    wget -q "https://github.com/nagios-plugins/nagios-plugins/releases/download/release-${NAGIOS_PLUGINS_VERSION}/nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz"
    tar xzf "nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz"
    cd "nagios-plugins-${NAGIOS_PLUGINS_VERSION}"
    
    # Configure and compile
    log "Configuring and compiling plugins..."
    ./configure \
        --prefix="$NAGIOS_HOME" \
        --with-nagios-user="$NAGIOS_USER" \
        --with-nagios-group="$NAGIOS_GROUP" \
        >> "$LOG_FILE" 2>&1
    
    make >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1
    
    log_success "Nagios Plugins installation completed"
}

################################################################################
# NRPE AGENT INSTALLATION
################################################################################

install_nrpe() {
    log "Installing NRPE v$NRPE_VERSION..."
    
    cd /tmp
    
    # Download NRPE
    log "Downloading NRPE..."
    wget -q "https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-${NRPE_VERSION}/nrpe-${NRPE_VERSION}.tar.gz"
    tar xzf "nrpe-${NRPE_VERSION}.tar.gz"
    cd "nrpe-${NRPE_VERSION}"
    
    # Configure
    log "Configuring NRPE..."
    ./configure --enable-command-args >> "$LOG_FILE" 2>&1
    
    # Compile and install
    make all >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1
    
    # Install NRPE as service
    if [ "$OS" = "amzn" ]; then
        make install-init >> "$LOG_FILE" 2>&1
    else
        cp startup/default-xinetd /etc/xinetd.d/nrpe || true
        systemctl restart xinetd 2>/dev/null || true
    fi
    
    log_success "NRPE installation completed"
}

################################################################################
# WEB INTERFACE CONFIGURATION
################################################################################

setup_web_interface() {
    log "Setting up Nagios web interface..."
    
    # Set Nagios web directory permissions
    chown -R "$NAGIOS_USER:$NAGIOS_GROUP" "$NAGIOS_HOME/share"
    chown -R "$NAGIOS_USER:$NAGIOS_GROUP" "$NAGIOS_HOME/var"
    chown -R "$NAGIOS_USER:$NAGIOS_GROUP" "$NAGIOS_HOME/libexec"
    
    # Create htpasswd for Nagios web access
    log "Creating web authentication..."
    htpasswd -bc "$NAGIOS_HOME/etc/htpasswd.users" nagiosadmin nagios
    
    # Fix Apache configuration
    if [ "$OS" = "amzn" ]; then
        # Enable CGI module
        a2enmod cgi 2>/dev/null || true
        
        # Create Apache configuration
        cat > /etc/httpd/conf.d/nagios.conf << 'EOF'
Alias /nagios "/usr/local/nagios/share"
<Directory "/usr/local/nagios/share">
   AllowOverride None
   Order allow,deny
   Allow from all
   AuthName "Nagios Access"
   AuthType Basic
   AuthUserFile /usr/local/nagios/etc/htpasswd.users
   Require all granted
</Directory>

ScriptAlias /nagios/cgi-bin "/usr/local/nagios/libexec"
<Directory "/usr/local/nagios/libexec">
   AllowOverride None
   Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
   Order allow,deny
   Allow from all
   AuthName "Nagios Access"
   AuthType Basic
   AuthUserFile /usr/local/nagios/etc/htpasswd.users
   Require all granted
</Directory>
EOF
    else
        # Ubuntu/Debian
        cat > /etc/apache2/sites-available/nagios.conf << 'EOF'
Alias /nagios "/usr/local/nagios/share"
<Directory "/usr/local/nagios/share">
   AllowOverride None
   Order allow,deny
   Allow from all
   AuthName "Nagios Access"
   AuthType Basic
   AuthUserFile /usr/local/nagios/etc/htpasswd.users
   Require all granted
</Directory>

ScriptAlias /nagios/cgi-bin "/usr/local/nagios/libexec"
<Directory "/usr/local/nagios/libexec">
   AllowOverride None
   Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
   Order allow,deny
   Allow from all
   AuthName "Nagios Access"
   AuthType Basic
   AuthUserFile /usr/local/nagios/etc/htpasswd.users
   Require all granted
</Directory>
EOF
        a2ensite nagios.conf 2>/dev/null || true
    fi
    
    log_success "Web interface setup completed"
}

################################################################################
# SERVICE CONFIGURATION
################################################################################

setup_services() {
    log "Setting up services..."
    
    # Enable Apache
    if [ "$OS" = "amzn" ]; then
        systemctl enable httpd
        systemctl restart httpd
    else
        systemctl enable apache2
        a2enmod cgi 2>/dev/null || true
        a2enmod rewrite 2>/dev/null || true
        systemctl restart apache2
    fi
    
    # Enable Nagios
    systemctl enable nagios
    systemctl restart nagios
    
    # Enable NRPE
    if [ "$OS" = "amzn" ]; then
        systemctl enable nrpe 2>/dev/null || true
        systemctl start nrpe 2>/dev/null || true
    fi
    
    log_success "Services enabled and started"
}

################################################################################
# NAGIOS CONFIGURATION
################################################################################

configure_nagios() {
    log "Configuring Nagios..."
    
    # Create objects directory if not exists
    mkdir -p "$NAGIOS_HOME/etc/objects"
    
    # Enable configuration
    sed -i 's/^#cfg_file=.*localhost.cfg/cfg_file=\/usr\/local\/nagios\/etc\/objects\/localhost.cfg/' \
        "$NAGIOS_HOME/etc/nagios.cfg"
    
    # Create basic local configuration
    cat > "$NAGIOS_HOME/etc/objects/localhost.cfg" << 'EOF'
# Localhost Nagios Configuration

define host {
    use                     linux-server
    host_name               localhost
    address                 127.0.0.1
    alias                   Nagios Server
}

define service {
    use                     local-service
    host_name               localhost
    service_description     CPU Load
    check_command           check_local_load!5.0,4.0!10.0,6.0
}

define service {
    use                     local-service
    host_name               localhost
    service_description     Disk Usage
    check_command           check_local_disk!20%!10%!/
}

define service {
    use                     local-service
    host_name               localhost
    service_description     Memory Usage
    check_command           check_local_swap!20!10
}

define service {
    use                     local-service
    host_name               localhost
    service_description     HTTP
    check_command           check_http
}
EOF

    # Validate configuration
    log "Validating Nagios configuration..."
    "$NAGIOS_HOME/bin/nagios" -v "$NAGIOS_HOME/etc/nagios.cfg" >> "$LOG_FILE" 2>&1 || log_error "Configuration validation failed"
    
    log_success "Nagios configuration completed"
}

################################################################################
# FIREWALL CONFIGURATION
################################################################################

setup_firewall() {
    log "Configuring firewall..."
    
    if [ "$OS" = "amzn" ]; then
        # Amazon Linux uses firewalld or iptables
        if command -v firewall-cmd &> /dev/null; then
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --permanent --add-port=5667/tcp
            firewall-cmd --reload 2>/dev/null || true
        fi
    else
        # Ubuntu uses UFW or iptables
        if command -v ufw &> /dev/null; then
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw allow 5667/tcp
        fi
    fi
    
    log_success "Firewall configuration completed"
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
    log "Nagios Core Installation Started"
    log "OS: $OS"
    log "Timestamp: $(date)"
    log "=========================================="
    
    # Run installation steps
    prepare_system
    setup_users_groups
    install_nagios_core
    install_nagios_plugins
    install_nrpe
    setup_web_interface
    configure_nagios
    setup_services
    setup_firewall
    setup_cloudwatch
    
    log "=========================================="
    log_success "Nagios Installation Completed!"
    log "=========================================="
    log ""
    log "Access Nagios at: http://$(hostname -I | awk '{print $1}')/nagios"
    log "Username: nagiosadmin"
    log "Password: nagios"
    log ""
    log "⚠️  IMPORTANT: Change the default password immediately!"
    log "Run: sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin"
    log ""
    log "Configuration file: /usr/local/nagios/etc/nagios.cfg"
    log "Objects directory: /usr/local/nagios/etc/objects/"
    log "Log file: $LOG_FILE"
    log "=========================================="
}

# Run main function
main "$@"
