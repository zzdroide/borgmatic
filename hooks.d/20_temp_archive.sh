#!/bin/bash
set -euo pipefail
source helpers/common.py

server_user=$(yq .server_user /etc/borgmatic/config/constants.yaml)

# All `borgmatic` commands here use --commands="[]", otherwise this hook would recursively run again.

delete_temp() {
  borgmatic --commands="[]" --verbosity=-1 `# verbosity=0 prints a "Deleting archives" line` \
    delete --archive="$server_user(temp)"
}

grep_chunks_cache_lines() {
  awk '/Synchronizing chunks cache\.\.\./{show=1} show; /Done\./{exit}'
  cat >/dev/null  # Discards lines after "Done."
}

case "$1" in
  "$hook_before")
    # For simplicity, have at most one temporary archive.
    delete_temp

    # Create a dummy temp archive to sync chunks cache now. This way it doesn't fill the snapshot later.
    borgmatic --commands="[]" --verbosity=1 \
      --source-directories="[/nonexistent]" --no-source-directories-must-exist --healthchecks.states="[]" \
      create | grep_chunks_cache_lines
    delete_temp
    ;;

  "$hook_after")
    # Only after all other $hook_after hooks have succeeded, mark this archive as valid.
    borgmatic --commands="[]" borg -- rename "::$server_user(temp)" "$server_user-$(date +"%Y-%m-%d_%H:%M")"
    ;;
esac
