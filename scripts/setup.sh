#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../"

sudo add-apt-repository -y ppa:rapier1/hpnssh
sudo add-apt-repository -y ppa:costamagnagianfranco/borgbackup
sudo apt update

# shellcheck disable=SC2086
sudo apt install -y \
  borgbackup \
  hpnssh-client \
  wakeonlan \
  smartmontools \
  jq \
  pipx \
  libfuse-dev # To build specialfile

# TODO: install specialfile
#   make
#   sudo make install

sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
  pipx install borgmatic==2.0.7
# Exact version because the project doesn't follow semver  https://torsion.org/borgmatic/docs/how-to/upgrade/#versioning-and-breaking-changes

# This is like "ssh-keyscan {server_ip} >>~/.ssh/known_hosts"
# but using borgmatic to obtain {server_ip}.
borgmatic --verbosity=-2 \
  --override ssh_command="hpnssh \
    -oStrictHostKeyChecking=accept-new `# Automatically add to known_hosts` \
    -oBatchMode=yes
    -oPreferredAuthentications=null `# Fail authentication on purpose and close connection`" \
  info 2>/dev/null
