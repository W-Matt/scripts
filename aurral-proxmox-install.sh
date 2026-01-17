#!/usr/bin/env bash

# Aurral Proxmox LXC Installation Script
# Created for deploying Aurral music scrobbling service
# https://github.com/lklynet/aurral

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
CTID=""
HOSTNAME="aurral"
DISK_SIZE="8"
CORES="2"
MEMORY="2048"
STORAGE="local-lvm"
TEMPLATE_STORAGE="local"
NETWORK_BRIDGE="vmbr0"
NETWORK_IP="dhcp"
GATEWAY=""
UNPRIVILEGED="1"
START_ON_BOOT="1"

# Function to print colored messages
msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

msg_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to get next available CT ID
get_next_ctid() {
    local next_id=100
    while pct status $next_id &>/dev/null; do
        ((next_id++))
    done
    echo $next_id
}

# Function to display header
show_header() {
    clear
    cat << "EOF"
    ___                        __
   /   | __  _______________  _/ /
  / /| |/ / / / ___/ ___/ __ `/ / 
 / ___ / /_/ / /  / /  / /_/ / /  
/_/  |_\__,_/_/  /_/   \__,_/_/   
                                  
Proxmox LXC Installation Script
EOF
    echo ""
}

# Function to get user inputs
get_user_input() {
    show_header
    
    # CT ID
    local suggested_ctid=$(get_next_ctid)
    read -p "Enter Container ID [$suggested_ctid]: " input_ctid
    CTID="${input_ctid:-$suggested_ctid}"
    
    # Hostname
    read -p "Enter Hostname [$HOSTNAME]: " input_hostname
    HOSTNAME="${input_hostname:-$HOSTNAME}"
    
    # Disk Size
    read -p "Enter Disk Size in GB [$DISK_SIZE]: " input_disk
    DISK_SIZE="${input_disk:-$DISK_SIZE}"
    
    # CPU Cores
    read -p "Enter CPU Cores [$CORES]: " input_cores
    CORES="${input_cores:-$CORES}"
    
    # Memory
    read -p "Enter Memory in MB [$MEMORY]: " input_memory
    MEMORY="${input_memory:-$MEMORY}"
    
    # Storage
    read -p "Enter Storage Pool [$STORAGE]: " input_storage
    STORAGE="${input_storage:-$STORAGE}"
    
    # Network Bridge
    read -p "Enter Network Bridge [$NETWORK_BRIDGE]: " input_bridge
    NETWORK_BRIDGE="${input_bridge:-$NETWORK_BRIDGE}"
    
    # IP Configuration
    read -p "Enter IP Address (DHCP or x.x.x.x/xx) [$NETWORK_IP]: " input_ip
    NETWORK_IP="${input_ip:-$NETWORK_IP}"
    
    if [[ "$NETWORK_IP" != "dhcp" ]]; then
        read -p "Enter Gateway IP: " input_gateway
        GATEWAY="$input_gateway"
    fi
    
    # Start on boot
    read -p "Start on boot? (1=yes, 0=no) [$START_ON_BOOT]: " input_boot
    START_ON_BOOT="${input_boot:-$START_ON_BOOT}"
    
    echo ""
    msg_info "Configuration Summary:"
    echo "  CT ID: $CTID"
    echo "  Hostname: $HOSTNAME"
    echo "  Disk: ${DISK_SIZE}GB"
    echo "  CPU Cores: $CORES"
    echo "  Memory: ${MEMORY}MB"
    echo "  Storage: $STORAGE"
    echo "  Network: $NETWORK_BRIDGE"
    echo "  IP: $NETWORK_IP"
    [[ -n "$GATEWAY" ]] && echo "  Gateway: $GATEWAY"
    echo "  Start on boot: $START_ON_BOOT"
    echo ""
    
    read -p "Proceed with installation? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        msg_error "Installation cancelled"
        exit 1
    fi
}

# Function to download Ubuntu template if needed
download_template() {
    local template="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    local template_path="$TEMPLATE_STORAGE:vztmpl/$template"
    
    msg_info "Checking for Ubuntu 24.04 template..."
    
    if ! pveam list $TEMPLATE_STORAGE | grep -q "$template"; then
        msg_warn "Template not found, downloading..."
        pveam download $TEMPLATE_STORAGE $template
        msg_ok "Template downloaded"
    else
        msg_ok "Template found"
    fi
    
    echo "$template_path"
}

# Function to create LXC container
create_container() {
    local template=$1
    
    msg_info "Creating LXC container..."
    
    local net_config="name=eth0,bridge=$NETWORK_BRIDGE,firewall=1"
    if [[ "$NETWORK_IP" == "dhcp" ]]; then
        net_config="$net_config,ip=dhcp"
    else
        net_config="$net_config,ip=$NETWORK_IP"
        [[ -n "$GATEWAY" ]] && net_config="$net_config,gw=$GATEWAY"
    fi
    
    pct create $CTID $template \
        --hostname $HOSTNAME \
        --cores $CORES \
        --memory $MEMORY \
        --rootfs $STORAGE:$DISK_SIZE \
        --net0 $net_config \
        --unprivileged $UNPRIVILEGED \
        --onboot $START_ON_BOOT \
        --features nesting=1 \
        --ostype ubuntu \
        --password $(openssl rand -base64 12)
    
    msg_ok "Container created (ID: $CTID)"
}

# Function to configure container for Docker
configure_container() {
    msg_info "Configuring container for Docker..."
    
    # Add nesting feature for Docker
    pct set $CTID -features nesting=1
    
    # Set keyctl to 1 for Docker
    echo "lxc.apparmor.profile: unconfined" >> /etc/pve/lxc/${CTID}.conf
    echo "lxc.cgroup2.devices.allow: a" >> /etc/pve/lxc/${CTID}.conf
    echo "lxc.cap.drop:" >> /etc/pve/lxc/${CTID}.conf
    echo "lxc.mount.auto: proc:rw sys:rw" >> /etc/pve/lxc/${CTID}.conf
    
    msg_ok "Container configured"
}

# Function to start container
start_container() {
    msg_info "Starting container..."
    pct start $CTID
    sleep 5
    msg_ok "Container started"
}

# Function to install dependencies inside container
install_dependencies() {
    msg_info "Installing system dependencies..."
    
    pct exec $CTID -- bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        lsb-release"
    
    msg_ok "System dependencies installed"
}

# Function to install Docker
install_docker() {
    msg_info "Installing Docker..."
    
    pct exec $CTID -- bash -c '
        # Add Docker GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        
        # Add Docker repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    '
    
    msg_ok "Docker installed"
}

# Function to clone and setup Aurral
setup_aurral() {
    msg_info "Cloning Aurral repository..."
    
    pct exec $CTID -- bash -c '
        cd /opt
        git clone https://github.com/lklynet/aurral.git
        cd aurral
        
        # Create .env file from example if it exists
        if [ -f .env.example ]; then
            cp .env.example .env
        else
            # Create basic .env file
            cat > .env << "ENVEOF"
# Aurral Environment Configuration
# Edit these values as needed

# Last.fm API (optional - for scrobbling)
LASTFM_API_KEY=
LASTFM_API_SECRET=

# Database (SQLite by default)
DATABASE_URL=sqlite:///data/aurral.db

# Server Configuration
PORT=8080
HOST=0.0.0.0

# Media Directory
MEDIA_DIR=/media

ENVEOF
        fi
        
        # Create media directory
        mkdir -p /opt/aurral/media
        
        # Set permissions
        chmod +x setup.sh 2>/dev/null || true
    '
    
    msg_ok "Aurral repository cloned"
}

# Function to start Aurral
start_aurral() {
    msg_info "Starting Aurral with Docker Compose..."
    
    pct exec $CTID -- bash -c 'cd /opt/aurral && docker compose up -d'
    
    msg_ok "Aurral started"
}

# Function to display completion message
show_completion() {
    local ip_address=$(pct exec $CTID -- hostname -I | awk '{print $1}')
    
    echo ""
    msg_ok "Installation complete!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Aurral is now running!"
    echo ""
    echo "  Container ID: $CTID"
    echo "  Hostname: $HOSTNAME"
    echo "  IP Address: $ip_address"
    echo ""
    echo "  Web Interface: http://$ip_address:8080"
    echo ""
    echo "  Configuration file: /opt/aurral/.env"
    echo "  Media directory: /opt/aurral/media"
    echo ""
    echo "  To access container:"
    echo "    pct enter $CTID"
    echo ""
    echo "  To manage Aurral:"
    echo "    cd /opt/aurral"
    echo "    docker compose stop"
    echo "    docker compose start"
    echo "    docker compose logs -f"
    echo ""
    echo "  To configure Last.fm API:"
    echo "    1. pct enter $CTID"
    echo "    2. nano /opt/aurral/.env"
    echo "    3. Add your API keys"
    echo "    4. docker compose restart"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Function to handle errors
handle_error() {
    msg_error "Installation failed at step: $1"
    msg_warn "You may need to manually clean up container $CTID"
    exit 1
}

# Main installation flow
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        msg_error "This script must be run as root"
        exit 1
    fi
    
    # Get user input
    get_user_input
    
    # Download template
    TEMPLATE=$(download_template) || handle_error "Template download"
    
    # Create container
    create_container "$TEMPLATE" || handle_error "Container creation"
    
    # Configure container
    configure_container || handle_error "Container configuration"
    
    # Start container
    start_container || handle_error "Container start"
    
    # Install dependencies
    install_dependencies || handle_error "Dependency installation"
    
    # Install Docker
    install_docker || handle_error "Docker installation"
    
    # Setup Aurral
    setup_aurral || handle_error "Aurral setup"
    
    # Start Aurral
    start_aurral || handle_error "Aurral startup"
    
    # Show completion message
    show_completion
}

# Run main function
main "$@"
