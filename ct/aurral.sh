#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2024 W-Matt
# Author: W-Matt
# License: MIT
# https://github.com/W-Matt/scripts/blob/main/LICENSE

function header_info {
clear
cat <<"EOF"
    ___                        __
   /   | __  _______________  _/ /
  / /| |/ / / / ___/ ___/ __ `/ / 
 / ___ / /_/ / /  / /  / /_/ / /  
/_/  |_\__,_/_/  /_/   \__,_/_/   
                                  
EOF
}
header_info
echo -e "Loading..."
APP="Aurral"
var_disk="8"
var_cpu="2"
var_ram="2048"
var_os="ubuntu"
var_version="22.04"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function update_script() {
header_info
if [[ ! -d /opt/aurral ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
msg_info "Updating ${APP}"
cd /opt/aurral
git pull
docker compose pull
docker compose up -d --force-recreate
msg_ok "Updated ${APP}"
exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}:8080${CL} \n"
