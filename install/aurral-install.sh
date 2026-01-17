#!/usr/bin/env bash

# Copyright (c) 2024 W-Matt
# Author: W-Matt
# License: MIT
# https://github.com/W-Matt/scripts/blob/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
$STD apt-get install -y git
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
cat >$DOCKER_CONFIG_PATH <<'EOF'
{
  "log-driver": "journald"
}
EOF
$STD sh <(curl -sSL https://get.docker.com)
msg_ok "Installed Docker"

msg_info "Pulling Aurral Docker Images"
$STD docker pull ghcr.io/lklynet/aurral-frontend:latest
$STD docker pull ghcr.io/lklynet/aurral-backend:latest
msg_ok "Pulled Aurral Docker Images"

msg_info "Installing Aurral"
mkdir -p /opt/aurral
cd /opt/aurral
$STD git clone https://github.com/lklynet/aurral.git /opt/aurral

# Create .env file
cat > /opt/aurral/.env <<'ENVEOF'
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
ENVEOF

# Create media and data directories
mkdir -p /opt/aurral/media
mkdir -p /opt/aurral/data

msg_ok "Installed Aurral"

msg_info "Creating Services"
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

systemctl enable --now aurral.service
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"

