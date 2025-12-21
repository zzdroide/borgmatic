#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../"


install_packages() {
  if (source /etc/os-release && [[ "$ID" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* ]]); then
    local is_ubuntu=1
  else
    local is_ubuntu=0
  fi

  if (source /etc/os-release && [[
    "$VERSION_CODENAME" == "focal" || "${UBUNTU_CODENAME:-}" == "focal"
  ]]); then
    echo "20.04 setup is not automated. Please install deadsnakes PPA and" \
        "pipx, and run setup.sh commands manually."
    exit 1
  fi

  local common_packages; common_packages="\
    curl \
    hpnssh-client \
    wakeonlan \
    smartmontools \
    jq \
    pipx \
    gawk \
    `# To build specialfile:` \
    build-essential \
    libfuse-dev"
  local extra_packages=""

  if (( is_ubuntu )); then
    sudo add-apt-repository -y ppa:rapier1/hpnssh
    sudo add-apt-repository -y ppa:costamagnagianfranco/borgbackup
    extra_packages="borgbackup"
  else
    manually_add_ppa_to_debian rapier1/hpnssh
    # Doesn't work:
    # manually_add_ppa_to_debian costamagnagianfranco/borgbackup

    # To build Borg  https://borgbackup.readthedocs.io/en/stable/installation.html#debian-ubuntu
    extra_packages="python3 python3-dev python3-pip python3-virtualenv libacl1-dev libssl-dev liblz4-dev libzstd-dev libxxhash-dev build-essential pkg-config libfuse3-dev fuse3"
  fi

  sudo apt update
  # shellcheck disable=SC2086
  sudo apt install -y $common_packages $extra_packages

  local set_pix_global_vars="PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin"

  local borgmatic_version=2.0.7  # Exact version because the project doesn't follow semver  https://torsion.org/borgmatic/docs/how-to/upgrade/#versioning-and-breaking-changes
  # Use < 2.0.8 while the mandatory check exists  https://projects.torsion.org/borgmatic-collective/borgmatic/pulls/1144#user-content-considerations
  # shellcheck disable=SC2086
  sudo $set_pix_global_vars pipx install borgmatic==$borgmatic_version

  # shellcheck disable=SC2086
  (( is_ubuntu )) || sudo $set_pix_global_vars pipx install "borgbackup~=1.4"
  true
}

manually_add_ppa_to_debian () {
  local name=$1
  local user="${name%%/*}"
  local repo="${name##*/}"
  keyfile=/etc/apt/keyrings/$user-$repo.gpg
  ppa_url=http://ppa.launchpadcontent.net/$name/ubuntu/
  echo "deb [signed-by=$keyfile] $ppa_url $(get_ubuntu_compatible_codename) main" |
    sudo tee "/etc/apt/sources.list.d/$user-$repo.list" >/dev/null

  sudo mkdir -p "$(dirname "$keyfile")"
  sudo rm -f "$keyfile"  # Because gpg only has "--yes", no "--overwrite"
  key_fingerprint=0x$(curl -fsS "https://launchpad.net/api/1.0/~$user/+archive/$repo" |
    python3 -c "import sys, json; print(json.load(sys.stdin)['signing_key_fingerprint'])")
  curl -fsS "https://keyserver.ubuntu.com/pks/lookup?op=get&search=$key_fingerprint" |
    sudo gpg --batch --dearmor -o "$keyfile"
}

get_ubuntu_compatible_codename() {
  # https://askubuntu.com/questions/445487/what-debian-version-are-the-different-ubuntu-versions-based-on
  (
    source /etc/os-release
    case "$VERSION_CODENAME" in
      bookworm) echo jammy;;
      trixie) echo noble;;
      *)
        echo "Unsupported Debian version: $VERSION_CODENAME"
        exit 1
        ;;
    esac
  )
}

keyscan_server() {
  echo -n "Running keyscan_server... "
  # This is like "ssh-keyscan {server_ip} >>~/.ssh/known_hosts" but also testing borgmatic,
  # and using it to obtain {server_ip} and wakeup_server.

  local output; output=$(
    borgmatic --verbosity=-1 \
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

install_specialfile() {
  local tmpdir; tmpdir=$(mktemp --directory --tmpdir specialfile.XXXX)
  pushd "$tmpdir" >/dev/null

  git clone --depth 1 https://github.com/zzdroide/specialfile .
  make
  sudo make install

  popd >/dev/null
  rm -rf "$tmpdir"
}

download_yq() {
  # I don't want to install yq globally, because there are two competing projects.
  local path="/etc/borgmatic/.bin"   # Not the nicest place though
  sudo mkdir -p "$path"

  local platform; platform="linux_$(dpkg --print-architecture)"
  curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_$platform.tar.gz" |
    sudo tar xz -C $path "./yq_$platform"
  sudo mv "$path/yq_$platform" "$path/yq"
}

diagnose_ssh_server() {
  local BLUE='\033[1;34m'
  local NO_COLOR='\033[0m'
  echo -e "$BLUE"

  local installed=1
  case "$(systemctl is-enabled ssh 2>&1 || true)" in
    "Failed to get unit file state for ssh.service: No such file or directory")
      echo ""
      echo "If you want automatic backups, you should run:"
      echo "  sudo apt install openssh-server"
      installed=0
      ;;
    disabled)
      echo ""
      echo "If you want automatic backups, you should run:"
      echo "  sudo systemctl enable --now ssh"
      ;;
  esac

  if (( installed )); then
    if ! sudo grep -REq "^\s*PasswordAuthentication\s+no\s*" /etc/ssh/; then
      echo ""
      echo "Note that sshd is defaulting to allow password authentication."
    fi
  fi

  echo -e "$NO_COLOR"
}



install_packages
keyscan_server
install_specialfile
download_yq
diagnose_ssh_server
