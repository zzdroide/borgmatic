#!/bin/bash
(( EUID == 0 )) || { echo "Not root"; exit 2; }
cd "$(dirname "$0")" || exit 2

# shellcheck disable=SC2002   # More readable order
cat ../config/smarthealthc.cfg | while read -r hc_url dev; do
  output=$(./check_disk.sh "$dev")
  rc=$?
  # On 16, just log. No success or failure.
  (( rc == 16)) && last_path=log || last_path=$rc

  url=$hc_url/$last_path
  curl -fsS -m 10 --retry 5 -o /dev/null --data-raw "$output" "$url"
done
