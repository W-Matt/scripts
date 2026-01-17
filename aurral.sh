#!/usr/bin/env bash

# Aurral Proxmox LXC - All-in-One Installation Script
# Copyright (c) 2024 W-Matt
# License: MIT
# Source: https://github.com/lklynet/aurral

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg_info() { echo -e "${BLUE}⚙️  $1${NC}"; }
msg_ok() { echo -e "${GREEN}✔️  $1${NC}"; }
msg_error() { echo -e "${RED}✖️  $1${NC}"; exit 1; }

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

# Configuration
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

msg_info "Using Default Settings on node $(hostname)"
echo "  💡  PVE Version $(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}') (Kernel: $(uname -r))"
echo "  🆔  Container ID: $CTID"
echo "  🖥️  Operating System: $OS_TYPE ($OS_VERSION)"
echo "  📦  Container Type: Unprivileged"
echo "  💾  Disk Size: ${DISK_SIZE} GB"
echo "  🧠  CPU Cores: $CORES"
echo "  🛠️  RAM Size: ${MEMORY} MiB"
echo ""
msg_info "Creating a $APP LXC using the above default settings"
echo ""

# Download template if needed
TEMPLATE="$OS_TYPE-$OS_VERSION-standard_${OS_VERSION}-1_amd64.tar.zst"
msg_info "Checking for template..."
if ! pveam list $TEMPLATE_STORAGE | grep -q "$TEMPLATE"; then
    msg_info "Downloading template..."
    pveam download $TEMPLATE_STORAGE $TEMPLATE >/dev/null 2>&1
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

# Install everything inside the container
msg_info "Installing system updates..."
pct exec $CTID -- bash -c "apt-get update >/dev/null 2>&1"
msg_ok "System updated"

msg_info "Installing Dependencies"
pct exec $CTID -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y curl sudo mc git >/dev/null 2>&1"
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
pct exec $CTID -- bash -c '
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'"'"'EOF'"'"'
{
  "log-driver": "journald"
}
EOF
curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
'
msg_ok "Installed Docker"

msg_info "Installing Aurral"
pct exec $CTID -- bash -c '
git clone https://github.com/lklynet/aurral.git /opt/aurral >/dev/null 2>&1
cd /opt/aurral

cat > .env <<'"'"'EOF'"'"'
# Aurral Environment Configuration
# Last.fm API (optional - for scrobbling)
LASTFM_API_KEY=
LASTFM_API_SECRET=

# Database
DATABASE_URL=sqlite:///data/aurral.db

# Server Configuration
PORT=8080
HOST=0.0.0.0

# Media Directory
MEDIA_DIR=/media
EOF

mkdir -p media data
'
msg_ok "Installed Aurral"

msg_info "Pulling Docker Images"
pct exec $CTID -- bash -c 'cd /opt/aurral && docker compose pull >/dev/null 2>&1'
msg_ok "Pulled Docker Images"

msg_info "Creating Services"
pct exec $CTID -- bash -c '
cat > /etc/systemd/system/aurral.service <<'"'"'EOF'"'"'
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

systemctl daemon-reload
systemctl enable --now aurral.service >/dev/null 2>&1
'
msg_ok "Created Services"

msg_info "Customizing Container"
pct exec $CTID -- bash -c '
cat > /etc/motd <<EOF
    ___                        __
   /   | __  _______________  _/ /
  / /| |/ / / / ___/ ___/ __ `/ / 
 / ___ / /_/ / /  / /  / /_/ / /  
/_/  |_\__,_/_/  /_/   \__,_/_/   

 Aurral Music Service
 
 Access: http://$(hostname -I | awk '"'"'{print $1}'"'"'):8080
 
EOF
'
msg_ok "Customized Container"

msg_info "Cleaning up"
pct exec $CTID -- bash -c "apt-get autoremove -y >/dev/null 2>&1 && apt-get autoclean >/dev/null 2>&1"
msg_ok "Cleaned"

echo ""
msg_ok "Completed successfully!"
echo ""
echo -e "  🚀  ${GREEN}Aurral setup has been successfully initialized!${NC}"
echo -e "  💡  Access it using the following URL:"
echo -e "    🌐  ${BLUE}http://${IP}:8080${NC}"
echo ""
