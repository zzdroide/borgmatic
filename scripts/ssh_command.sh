#!/bin/bash

# Use HPN SSH with some options, as the original user if sudo was used.
# Also filters stderr.

filter_stderr() {
  grep -v "WARNING: ENABLED NONE CIPHER!!!"
}

exec sudo -u "${SUDO_USER:-$USER}" \
  SSH_AUTH_SOCK="$SSH_AUTH_SOCK" `# Provides unlocked identity_file` \
  hpnssh -p1701 -oBatchMode=yes -oNoneEnabled=yes -oNoneSwitch=yes "$@" \
2> >(filter_stderr >&2)

# https://unix.stackexchange.com/questions/3514/how-to-grep-standard-error-stream-stderr/3540#3540
