#!/bin/bash
set -euo pipefail

# This script runs every time the computer wakes up.
# Maybe the user waked up the computer to use it, and this script should just exit.
# Or maybe tamborg server sent us a WOL to backup now. Check for that.
# (Or maybe tamborg server ran 'sudo systemctl start tamborgmatic-auto.service';
# in that case, the following check is harmless)

### Check if waiting_for me ###

PATH="/etc/borgmatic/.bin:$PATH"
server_ip=$(  yq .server_ip   /etc/borgmatic/config/constants.yaml)
server_user=$(yq .server_user /etc/borgmatic/config/constants.yaml)
server_repo=$(yq .server_repo /etc/borgmatic/config/constants.yaml)

# Wait for network connectivity after resume from suspend
for _ in $(seq 1 30); do
  ip route get "$server_ip" &>/dev/null && break
  sleep 1
done
# Note: nm-online didn't work

waiting_for=$(curl -fs --max-time 5 "http://$server_ip:8087/$server_repo" || true)

if [[ "$waiting_for" != "$server_user" ]]; then
  # Nope, just a regular wakeup.
  exit 0
fi

### waiting_for me: signal borg_daily that we're up ###

# Dummy command to open a borg session on server:
borgmatic --verbosity=-1 --commands=[] borg with-lock :: true
# That command signals borg_daily that we received the WOL and should wait for us.
# Otherwise, if hooks take too long:
# - either a long timeout is required on borg_daily,
# - or borg_daily times out checking if we woke up or not.
# The signaling method is a remote borg command,
# because `borg serve` over ssh is the only allowed access to the server.

### Run in GUI or headless ###

if systemctl is-active --quiet display-manager; then
  # The computer is running a GUI. Run visibly so that user knows what's going on,
  # and keep terminal open so user knows why is the computer awake.

  export DISPLAY=:0
  export XAUTHORITY="$HOME/.Xauthority"
  cmd="/etc/borgmatic/run_create.py; printf '\n[Finished - Press Enter to close]'; read _"
  gnome-terminal --wait --maximize --title="tamborgmatic run_create" -- sh -c "$cmd"

  # Leave computer on after run_create finishes,
  # because user could be using it, and shouldn't sleep unexpectedly.
  # Assume it will sleep on its own about 15min after run_create's suspend inhibit ends.

else  # Headless

  if [[ -z ${SSH_AUTH_SOCK:-} ]]; then
    eval "$(ssh-agent)"  # For root to use $USER's ssh key
    trap 'ssh-agent -k' EXIT
  fi

  exec /etc/borgmatic/run_create.py
fi
