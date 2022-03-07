# shellcheck shell=bash
# shellcheck disable=SC2034 # This file is to be sourced

root_borg_dirs_exist() {
  [[ -e /root/.config/borg/ || -e /root/.cache/borg/ ]]
}
readonly ROOT_BORG_DIRS_EXIST_MSG="Warning: borg config and/or cache exists in /root" # in my usecase this shouldn't happen, it's a bug.
# Alternative: hardcode repo id (as `borg config repo id` doesn't work for remote repos), and check those dirs.
