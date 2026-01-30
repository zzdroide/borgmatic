#!/bin/bash
set -euo pipefail
source helpers/common.py

server_user=$(yq .server_user /etc/borgmatic/config/constants.yaml)

# All `borgmatic` commands here use --commands="[]", otherwise this hook would recursively run again.
# Also, some commands use --verbosity=1 to prevent printing a "Running arbitrary Borg command" line.

grep_chunks_cache_lines() {
  awk '/Synchronizing chunks cache\.\.\./{show=1} show; /Done\./{exit}'
  cat >/dev/null  # Discards lines after "Done."
}

case "$1" in
  "$hook_before")
    # Create a dummy temp archive to sync chunks cache now. This way it doesn't fill the snapshot later.
    borgmatic --commands="[]" --verbosity=1 \
      --source-directories="[/nonexistent]" --no-source-directories-must-exist --healthchecks.states="[]" \
      create | grep_chunks_cache_lines
    ;;

  "$hook_after")
    # Only after all other $hook_after hooks have succeeded, mark this archive as valid.

    latest_temp_archive=$(borgmatic --commands="[]" --verbosity=0 \
      list --short --glob-archives="$server_user(temp)-*" | tail -n1)

    borgmatic --commands="[]" --verbosity=-1 \
      borg -- rename "::$latest_temp_archive" "${latest_temp_archive/(temp)/}"

    # Note: having a single temp archive per $server_user is simpler (just "$server_user(temp)"),
    # but it has to be deleted before running `borgmatic create`, and that's a problem.
    #
    # Details:
    # Deletion didn't take too long over LAN, but over higher latency internet it was too much.
    # `borg delete` sends a lot of requests to the server: one per chunk referenced in the archive,
    # see https://github.com/borgbackup/borg/blob/509c569/src/borg/archive.py#L1033.
    # Even if fetch_async_response is called with wait=False,
    # the SSH buffer fills up and the client blocks until the server catches up.
    ;;
esac
