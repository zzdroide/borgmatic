#!/bin/bash
set -euo pipefail
source helpers/common.py

# Checks HDD SMART statuses, and reports them to healthchecks (like the backups).
#
# (I didn't investigate this much, may be wrong:)
# The `smartmontools` package provides a systemd _smartmontools.service_, but:
# - It reports to the systemd journal which nobody reads
# - It uses the SMART result from the manufacturer, which is too optimistic.
#   Instead, this script uses a stricter assessment, from empirical data
#   (see `backblaze_attrs` in code).
#
# So I prefer to roll my own.
#
# The original idea was to make this a separate project
# and periodically run it with cron or a systemd timer,
# but they don't work well for systems that are not active 24/7 (see
# https://unix.stackexchange.com/questions/742513/a-monotonic-systemd-timer-that-is-not-distorted-by-suspension-and-downtime
# , and https://askubuntu.com/questions/1392023/what-will-make-unattended-upgrades-run-reliably-on-a-laptop
# at the bottom of the question).
#
# So trigger this together with the backup, which should happen periodically as well.


loop_disks() {
  {
    grep -v \
    -e '^\s*$' `# Skip empty or whitespace-only lines` \
    -e '^#'    `# Skip comments` \
    ../config/smarthealthc.cfg || true;
  } | while read -r hc_url dev; do

    if [[ ! $dev ]]; then
      echo "Bad line in smarthealthc.cfg:"
      echo "  $hc_url $dev"
      exit 1
    fi

    local rc=0
    local output; output=$(helpers/smart_check_disk.sh "$dev") || rc=$?

    # rc=0: success
    # rc=1: failure
    # rc>1: just log. No success or failure.
    local action
    if (( rc == 1 )); then
      action=fail
    elif (( rc > 1 )); then
      action=log
    else
      action="0"
    fi

    local url=$hc_url/$action
    curl -fsS -m 10 --retry 5 -o /dev/null --data-raw "$output" "$url" || true
  done
}

case "$1" in
  "$hook_after") loop_disks ;;
esac
