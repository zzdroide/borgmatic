# This is a hack to define consts only once, and source a single file.  # noqa: INP001

# shellcheck shell=bash
# shellcheck disable=SC2034 # This file is to be sourced
# ruff: noqa: Q001, E225, E261, E262, E303

# This file is valid bash and python,
# and python executes `foo="bar"`,
# and bash `readonly foo="bar"`.

_=''''
# Prevent spam when debugging
_previous_options=$-
set +x
#'''


_='''' readonly `#'''#` \
hook_before="before"
_='''' readonly `#'''#` \
hook_after="after"
_='''' readonly `#'''#` \
hook_cleanup="cleanup"

_='''' readonly `#'''#` \
base_dir="/mnt/tamborgmatic"
_='''' readonly `#'''#` \
merged_dir="/mnt/tamborgmatic/merged"
_='''' readonly `#'''#` \
specialfile_dir="/mnt/tamborgmatic/specialfile"
_='''' readonly `#'''#` \
src_dir="/mnt/tamborgmatic/src"
_='''' readonly `#'''#` \
tmp_dir="/mnt/tamborgmatic/tmp"
_='''' readonly `#'''#` \
post_mounts="/mnt/tamborgmatic/tmp/post_mounts.sh"
_='''' readonly `#'''#` \
error_flag="/mnt/tamborgmatic/tmp/error.flag"

_='''' readonly `#'''#` \
bupsrcs_path="../config/bupsrcs.cfg"
_='''' readonly `#'''#` \
target_part="part"
_='''' readonly `#'''#` \
target_data="data"
_='''' readonly `#'''#` \
target_linux="linux"




_=r''''

declare -A bupsrc

is_bupsrc_target_part() {
    [[ "${bupsrc[target]}" == "$target_part" ]]
}
is_bupsrc_target_data() {
    [[ "${bupsrc[target]}" == "$target_data" ]]
}
is_bupsrc_target_linux() {
    [[ "${bupsrc[target]}" == "$target_linux" ]]
}

_set_devpart_devlv() {
    if is_bupsrc_target_linux; then
        bupsrc[devlv]=$(findmnt --noheadings --output source "${bupsrc[path]}")
        bupsrc[devpart]=$(lvs --noheadings -o devices "${bupsrc[devlv]}" | sed -E "s/\s*(.+)\(0\)/\1/")
    else
        # bupsrc[devlv] intentionally unset
        bupsrc[devpart]=$(realpath "${bupsrc[path]}")
    fi
}

_print_is_ntfs() {
    local fstype; fstype=$(lsblk --noheadings --output fstype "${bupsrc[devpart]}")
    [[ $fstype == ntfs ]] && echo 1 || echo 0
}

# Process substitution instead of pipe because of https://www.shellcheck.net/wiki/SC2030
< <(grep -v \
    -e '^\s*$' `# Skip empty or whitespace-only lines` \
    -e '^#'    `# Skip comments` \
    "$bupsrcs_path") \
        readarray -t _bupsrcs

reset_bupsrc() {
    _i=0
}

reset_bupsrc

# It would have been great for this function to "yield bupsrc",
# but this limited programming language isn't well suited
# to handle a structure more complex than a string.
#
# So the function returns code 1 for "StopIteration",
# and writes the result to the global variable "bupsrc".
next_bupsrc() {
    if (( _i >= ${#_bupsrcs[@]} )); then    # if _i >= len(_bupsrcs):
        return 1
    fi

    local target name path
    read -r target name path <<< "${_bupsrcs[$((_i++))]}"

    if [[ ! $path ]]; then
        echo "Bad line in $(basename $bupsrcs_path):"
        echo "  $target $name $path"
        exit 1
    fi

    case "$target" in
        "$target_part" | "$target_data" | "$target_linux")
            ;;
        *)
            echo "Bad target in $(basename $bupsrcs_path): $target"
            exit 1
            ;;
    esac

    bupsrc=(
        [target]=$target
        [name]=$name
        [path]=$path
    )
    _set_devpart_devlv
    bupsrc[ntfs]=$(_print_is_ntfs)

    # bupsrc[path] is an uuid for stability,  (/dev/disk/by-partuuid/asdf1234)
    # but usage of bupsrc[devpart] is preferred for readability when debugging commands.  (/dev/sda1)
}

#'''

_=''''
echo $_previous_options | grep -q x && set -x
unset _previous_options
#'''
