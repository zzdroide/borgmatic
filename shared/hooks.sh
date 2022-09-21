# shellcheck shell=bash
# shellcheck disable=SC2034 # This file is to be sourced


readonly BEFORE="before"
readonly AFTER="after"
readonly CLEANUP="cleanup"
readonly HOOKS=("$BEFORE" "$AFTER" "$CLEANUP")

# shellcheck disable=SC2076
if [[ ! " ${HOOKS[*]} " =~ " $HOOK_TYPE " ]]; then  # if HOOK_TYPE not in HOOKS  https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
  echo "Bad hook type: [$HOOK_TYPE]"
  exit 1
fi


root_borg_dirs_exist() {
  [[ -e /root/.config/borg/ || -e /root/.cache/borg/ ]]
}
readonly ROOT_BORG_DIRS_EXIST_MSG="Warning: borg config and/or cache exists in /root" # in my usecase this shouldn't happen, it's a bug.
# Alternative: hardcode repo id (as `borg config repo id` doesn't work for remote repos), and check those dirs.
