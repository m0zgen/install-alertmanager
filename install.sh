#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# Install Prometheus AlertManager as a systemd service

set -e

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)
cd $SCRIPT_PATH

_USER=alertmanager
_SERVICE=alertmanager
_DOWNLOADS=downloads
_TAR_TARGET=alertmanager
_LATEST_RELEASE=`curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | grep browser_download_url | grep "linux-amd64" | awk '{print $2}' | tr -d '\"'`
# http://127.0.0.1:9087/alert/<chat_ID> or use another URL like a Slack hook
_ALERT_URL=http://127.0.0.1:9087/alert/
_SERVER_IP=`/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2}'`

# Fncs
# ---------------------------------------------------\

# Help information
usage() {

  echo -e "\nArguments:
  -u (SUninstall alertmanager if exists)
  "
  exit 1
}

# Checks arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -u|--unistall) _UNINSTALL=1; ;;
        -h|--help) usage ;; 
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
done

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

# Checks supporting distros
checkDistro() {
    # Checking distro
    if [ -e /etc/centos-release ]; then
        DISTRO=`cat /etc/redhat-release | awk '{print $1,$4}'`
        RPM=1
    elif [ -e /etc/fedora-release ]; then
        DISTRO=`cat /etc/fedora-release | awk '{print ($1,$3~/^[0-9]/?$3:$4)}'`
        RPM=2
    elif [ -e /etc/os-release ]; then
        DISTRO=`lsb_release -d | awk -F"\t" '{print $2}'`
        RPM=0
        DEB=1
    else
        Error "Your distribution is not supported (yet)"
        exit 1
    fi
}

getDate() {
    date '+%d-%m-%Y_%H-%M-%S'
}

service_active() {
    local n=$1
    if [[ $(systemctl list-units --type=service --state=active | grep $n.service | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
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

installs() {

  if [[ ! "$(command -v $2)" ]]; then
        $1 -y install $2
  fi

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



uninstall() {

  local _BKP=$SCRIPT_PATH/backup

  if service_active "$_SERVICE"; then
    systemctl stop $_SERVICE.service
  fi

  check_dir $_BKP

  if [[ -f /lib/systemd/system/alertmanager.service ]]; then
      cp /lib/systemd/system/alertmanager.service "$_BKP/alertmanager.service_$(getDate).bkp"
      rm -f /lib/systemd/system/alertmanager.service
      systemctl daemon-reload
  fi

  if [[ -f /etc/alertmanager/alertmanager.yml ]]; then
      cp /etc/alertmanager/alertmanager.yml "$_BKP/alertmanager.yml_$(getDate).bkp"
      rm -f /lib/systemd/system/alertmanager.service
  fi

  if [[ -f /usr/local/bin/alertmanager ]]; then
      rm -f /usr/local/bin/alertmanager
  fi

  if [[ -f /usr/local/bin/amtool ]]; then
      rm -f /usr/local/bin/amtool
  fi

  echo "Backups located in: $_BKP"
  echo "Done."

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

    exit 0

}

# Acts
# ---------------------------------------------------\

isRoot
checkDistro

if [[ "$_UNINSTALL" -eq "1" ]]; then
  uninstall
  exit 0
fi

if [[ "$RPM" -eq "1" ]]; then
    echo "CentOS detected..."
    installs "yum" "wget"
elif [[ "$RPM" -eq "2" ]]; then
    echo "Fedora detected... "
    installs "dnf" "wget"
elif [[ "$DEB" -eq "1" ]]; then
    echo "Debian detected... "
    installs "apt" "wget"
else
    echo "Unknown distro. Exit."
    exit 1
fi

#
init