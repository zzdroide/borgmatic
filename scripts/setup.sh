#!/bin/bash
set -euo pipefail

# https://stackoverflow.com/questions/73764339/pipx-fails-for-poetry-on-ubuntu-20-04
[[ $(source /etc/os-release && echo "$UBUNTU_CODENAME") == "focal" ]] \
  && pipx_apt= \
  || pipx_apt=pipx

sudo add-apt-repository -y ppa:rapier1/hpnssh
sudo apt update

# shellcheck disable=SC2086
sudo apt install -y \
  `# To build Borg  # https://borgbackup.readthedocs.io/en/2.0.0b7/installation.html#debian-ubuntu` \
  python3 python3-dev python3-pip python3-virtualenv libacl1-dev libacl1 libssl-dev liblz4-dev \
  libzstd-dev libxxhash-dev build-essential pkg-config python3-pkgconfig libfuse3-dev fuse3 \
  \
  hpnssh-client \
  wakeonlan smartmontools jq $pipx_apt

if [[ -z "$pipx_apt" ]]; then
  sudo pip3 install pipx
fi

sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
  pipx install 'borgbackup[pyfuse3]==2.0.0b7' --suffix 2
# Exact version because betas can have breaking changes.
# Future: use a PPA

sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
  pipx install 'borgmatic==1.8.5' --suffix 2
# Exact version because the project doesn't follow semver
# (search for `BREAKING` in the changelog: https://projects.torsion.org/borgmatic-collective/borgmatic/src/branch/master/NEWS)
