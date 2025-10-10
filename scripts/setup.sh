#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../"


install_specialfile() {
  local tmpdir; tmpdir=$(mktemp --directory --tmpdir specialfile.XXXX)
  pushd "$tmpdir" >/dev/null

  git clone --depth 1 https://github.com/zzdroide/specialfile .
  make
  sudo make install

  popd >/dev/null
  rm -rf "$tmpdir"
}

keyscan_server() {
  echo -n "Running keyscan_server... "
  # This is like "ssh-keyscan {server_ip} >>~/.ssh/known_hosts"
  # but using borgmatic to obtain {server_ip} and wakeup_server.

  local output
  output=$(borgmatic --verbosity=-1 \
    --ssh-command="hpnssh \
      -p1701 \
      -oStrictHostKeyChecking=accept-new  `# Automatically add to known_hosts` \
      -oBatchMode=yes \
      -oPreferredAuthentications=null"    `# Fail authentication on purpose and close connection` \
    `# Check if the entry got written into ~/.ssh/known_hosts:` \
    "--commands[0].run[0]=ssh-keygen -F '[{server_ip}]:1701' >/dev/null && echo ok_known_host_found" \
    info 2>&1 || true)

  if [[ "$output" == *ok_known_host_found* ]]; then
    echo "ok"
  else
    echo -e "\nkeyscan_server failed:"
    echo "$output"
    exit 1
  fi
}



if (source /etc/os-release && [[
  "$VERSION_CODENAME" == "focal" || "$UBUNTU_CODENAME" == "focal"
]]); then
  echo "20.04 setup is not automated. Please install deadsnakes PPA and" \
       "pipx, and run setup.sh commands manually."
  exit 1
fi

sudo add-apt-repository -y ppa:rapier1/hpnssh
sudo add-apt-repository -y ppa:costamagnagianfranco/borgbackup
sudo apt update
sudo apt install -y \
  borgbackup \
  hpnssh-client \
  wakeonlan \
  smartmontools \
  jq \
  pipx \
  `# To build specialfile:` \
  build-essential \
  libfuse-dev

sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install borgmatic==2.0.9
# Exact version because the project doesn't follow semver  https://torsion.org/borgmatic/docs/how-to/upgrade/#versioning-and-breaking-changes

keyscan_server
install_specialfile
