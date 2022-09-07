#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# Install Prometheus AlertManager as a systemd service

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)
cd $SCRIPT_PATH

_DOWNLOADS=downloads
_TAR_TARGET=alertmanager
_LATEST_RELEASE=`curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | grep browser_download_url | grep "linux-amd64" | awk '{print $2}' | tr -d '\"'`
# http://127.0.0.1:9087/alert/<chat_ID> or use another URL like a Slack hook
_ALERT_URL=http://127.0.0.1:9087/alert/
_SERVER_IP=`/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2}'`
_USER=alertmanager
# Fncs
# ---------------------------------------------------\

# Check is current user is root
isRoot() {
  if [ $(id -u) -ne 0 ]; then
    echo "You must be root user to continue"
    exit 1
  fi
  RID=$(id -u root 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "User root no found. You should create it to continue"
    exit 1
  fi
  if [ $RID -ne 0 ]; then
    echo "User root UID not equals 0. User root must have UID 0"
    exit 1
  fi
}

function render_template() {
  eval "echo \"$(cat $1)\""
}
function push_template {
  render_template $1 > $2
}

final_steps() {
    echo -e "Please update target URL in /etc/alertmanager/alertmanager.yml"
    echo -e "Please update Alertmanager URL in /etc/prometheus/prometheus.yml"
}

check_dir() {

  if [[ ! -d "$1" ]]; then
    mkdir -p $1
  fi

}

get_status() {
  local _STATUS=`systemctl is-active alertmanager.service`
  echo "alertmanager.service has status: $_STATUS"
}

install_alertmanager() {

    cp  pkg/bin/* /usr/local/bin
    check_dir /etc/alertmanager
    check_dir /data/alertmanager

    if id -u "$_USER" >/dev/null 2>&1; then
        echo "User: $_USER already exists..."
    else
        echo "Creating user: $_USER .."
        useradd -rs /bin/false alertmanager
    fi

    push_template pkg/alertmanager_conf.tmpl /etc/alertmanager/alertmanager.yml
    chown -R alertmanager:alertmanager /data/alertmanager /etc/alertmanager

    push_template pkg/alertmanager_unit.tmpl /lib/systemd/system/alertmanager.service
    chown alertmanager:alertmanager /usr/local/bin/amtool /usr/local/bin/alertmanager

    systemctl daemon-reload
    systemctl enable --now alertmanager

}

init() {

    if [[ -f /lib/systemd/system/alertmanager.service ]]; then
      echo "Alertmanager daemon already installed..."
      echo "Checking status..."
      get_status
      exit 1
    elif [[ -f /etc/alertmanager/alertmanager.yml ]]; then
      echo "Alertmanager config already installed... Please verify previous installation."
      exit 1
    fi

    check_dir $SCRIPT_PATH/tmp
    check_dir $SCRIPT_PATH/pkg/bin/

    if [[ ! -d "$_DOWNLOADS" ]]; then
        mkdir -p "$_DOWNLOADS/$_TAR_TARGET"
      else
        rm -rf "$_DOWNLOADS"
        mkdir -p "$_DOWNLOADS/$_TAR_TARGET"
    fi

    cd "$_DOWNLOADS"
    echo "Download latest alertmanager release from GitHub..."
    wget "$_LATEST_RELEASE"
    tar xvf alertmanager*amd64.tar.gz --directory "$_TAR_TARGET"/

    local _BINARY_CATALOG=`ls "$_TAR_TARGET"`
    local _BINARY="$_DOWNLOADS"/"$_TAR_TARGET"/"$_BINARY_CATALOG"/alertmanager
    local _BINARY_TOOL="$_DOWNLOADS"/"$_TAR_TARGET"/"$_BINARY_CATALOG"/amtool
    
    cd $SCRIPT_PATH

    cp "$_BINARY" pkg/bin/
    cp "$_BINARY_TOOL" pkg/bin/

    install_alertmanager

}

# Acts
# ---------------------------------------------------\

isRoot
init
