#!/usr/bin/env bash

# Aurral LXC Build Script
# Copyright (c) 2024 W-Matt
# License: MIT

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
REPO="W-Matt/scripts"
BRANCH="main"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/install/aurral-install.sh"

# Default settings
APP="Aurral"
CTID=""
HOSTNAME="aurral"
DISK_SIZE="8"
CORES="2"
MEMORY="2048"
STORAGE="local-lvm"
TEMPLATE_STORAGE="local"
OS_TYPE="ubuntu"
OS_VERSION="22.04"

msg_info() { echo -e "${BLUE}⚙️  $1${NC}"; }
msg_ok() { echo -e "${GREEN}✔️  $1${NC}"; }
msg_error() { echo -e "${RED}✖️  $1${NC}"; }

header_info() {
clear
cat <<"EOF"
    ___                        __
   /   | __  _______________  _/ /
  / /| |/ / / / ___/ ___/ __ `/ / 
 / ___ / /_/ / /  / /  / /_/ / /  
/_/  |_\__,_/_/  /_/   \__,_/_/   
                                  
EOF
}

get_next_ctid() {
    local next_id=100
    while pct status $next_id &>/dev/null 2>&1; do
        ((next_id++))
    done
    echo $next_id
}

header_info
echo -e "Loading...\n"

# Get next available CT ID
CTID=$(get_next_ctid)

msg_info "Using Default Settings"
echo "  🆔  Container ID: $CTID"
echo "  🖥️  Operating System: $OS_TYPE ($OS_VERSION)"
echo "  💾  Disk Size: ${DISK_SIZE} GB"
echo "  🧠  CPU Cores: $CORES"
echo "  🛠️  RAM Size: ${MEMORY} MiB"
echo ""

# Download template if needed
TEMPLATE="$OS_TYPE-$OS_VERSION-standard_${OS_VERSION}-1_amd64.tar.zst"
msg_info "Checking for template..."
if ! pveam list $TEMPLATE_STORAGE | grep -q "$TEMPLATE"; then
    msg_info "Downloading template..."
    pveam download $TEMPLATE_STORAGE $TEMPLATE
fi
msg_ok "Template ready"

# Create container
msg_info "Creating LXC Container..."
pct create $CTID ${TEMPLATE_STORAGE}:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --cores $CORES \
    --memory $MEMORY \
    --rootfs $STORAGE:$DISK_SIZE \
    --net0 name=eth0,bridge=vmbr0,firewall=1,ip=dhcp \
    --unprivileged 1 \
    --onboot 1 \
    --features nesting=1 \
    --ostype ubuntu \
    --password $(openssl rand -base64 12) >/dev/null 2>&1

msg_ok "LXC Container $CTID created"

# Configure for Docker
cat >> /etc/pve/lxc/${CTID}.conf <<EOF
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.mount.auto: proc:rw sys:rw
EOF

# Start container
msg_info "Starting LXC Container..."
pct start $CTID
sleep 5
msg_ok "Started LXC Container"

# Wait for network
msg_info "Waiting for network..."
for i in {1..30}; do
    if pct exec $CTID -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
msg_ok "Network ready"

# Get IP address
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

# Download and run install script
msg_info "Running installation script..."
pct exec $CTID -- bash -c "$(wget -qLO - $INSTALL_SCRIPT_URL)" || {
    msg_error "Install script failed. Running manual installation..."
    
    # Fallback manual installation
    pct exec $CTID -- bash <<'EOFINSTALL'
    # Update system
    apt-get update
    apt-get install -y curl git sudo mc
    
    # Install Docker
    curl -fsSL https://get.docker.com | sh
    
    # Clone Aurral
    git clone https://github.com/lklynet/aurral.git /opt/aurral
    cd /opt/aurral
    
    # Create .env
    cat > .env <<'EOF'
LASTFM_API_KEY=
LASTFM_API_SECRET=
DATABASE_URL=sqlite:///data/aurral.db
PORT=8080
HOST=0.0.0.0
MEDIA_DIR=/media
EOF
    
    # Create directories
    mkdir -p media data
    
    # Create systemd service
    cat > /etc/systemd/system/aurral.service <<'EOF'
[Unit]
Description=Aurral Music Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/aurral
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable --now aurral.service
EOFINSTALL
}

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL."
echo -e "         ${BLUE}http://${IP}:8080${NC}\n"
