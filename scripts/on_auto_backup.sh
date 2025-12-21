#!/bin/bash
set -euo pipefail

gui=
wol=
while getopts "ghwo" opt; do
  case "$opt" in
    g) gui=1 ;;
    h) gui=0 ;;
    w) wol=1 ;;
    o) wol=0 ;;
    ?) exit 1
  esac
done
if [[ -z "$gui" ]]; then
  echo "Error: must specify -g or -h"
  exit 1
elif [[ -z "$wol" ]]; then
  echo "Error: must specify -w or -o"
  exit 1
fi

if (( wol )); then
  # Computer may have just woken up. Maybe it was user initiated,
  # maybe it was tamborg server WOL that wants to backup now. Check:
  PATH="/etc/borgmatic/.bin:$PATH"
  server_ip=$(  yq .server_ip   /etc/borgmatic/config/constants.yaml)
  server_user=$(yq .server_user /etc/borgmatic/config/constants.yaml)
  server_repo=$(yq .server_repo /etc/borgmatic/config/constants.yaml)

  waiting_for=$(curl -fs --max-time 5 "http://$server_ip:8087/$server_repo" || true)

  if [[ "$waiting_for" != "$server_user" ]]; then
    # Nope, just a regular wakeup.
    exit 0
  fi

  # Dummy command to open a borg session on server:
  borgmatic --verbosity=-1 --commands=[] borg with-lock :: true
  # That command signals borg_daily that we received the WOL and should wait for us.
  # Otherwise, if hooks take too long:
  # - either a long timeout is required on borg_daily,
  # - or borg_daily times out checking if we woke up or not.
fi

if (( gui )); then
  # Visibly so user knows what's going on,
  # and keep terminal open so user knows why is the computer awake.

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
