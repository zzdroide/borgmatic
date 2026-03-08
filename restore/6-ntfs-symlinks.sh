#!/bin/bash
set -euo pipefail

# Usage: 6-ntfs-symlinks.sh <folder_junctions|folder_symlinks> <source_dir> [target_dir]
# Example: 6-ntfs-symlinks.sh folder_junctions /mnt/borg/NTFS_PART /media/user/NTFS_PART

if [[ "$#" -lt 2 ]] || [[ "$#" -gt 3 ]]; then
  >&2 echo "Usage: $0 <folder_junctions|folder_symlinks> <source_dir> [target_dir]"
  exit 1
fi

MODE="$1"
SRC_DIR=$(realpath "$2")

if [[ "$MODE" != "folder_junctions" ]] && [[ "$MODE" != "folder_symlinks" ]]; then
  >&2 echo "Error: first argument must be 'folder_junctions' or 'folder_symlinks'"
  exit 1
fi

if [[ "$#" -eq 3 ]]; then
  TARGET_DIR="$3"
  exec >"$TARGET_DIR/tamborgmatic_restore_symlinks.bat"
fi

echo "@echo off"
echo "cd /d %~dp0"

# Prefix for absolute links in the mounted archive
ABS_PREFIX="/mnt/tamborgmatic/merged/$(basename "$SRC_DIR")/"

cd "$SRC_DIR"

# Find all symlinks
find . -type l | while read -r link_path; do
  # Remove leading ./ from link_path
  link_path="${link_path#./}"

  # Get the target of the symlink
  target=$(readlink "$link_path")

  is_absolute=false
  if [[ "$target" == /* ]]; then
    is_absolute=true
  fi

  if [[ "$is_absolute" == true ]]; then
    if [[ "$target" == "$ABS_PREFIX"* ]]; then
      # It's an absolute link within the expected prefix, remove the prefix
      target="${target#"$ABS_PREFIX"}"
    else
      >&2 echo "Error: Absolute link '$link_path' points outside expected prefix: $target"
      exit 1
    fi
  fi

  # Check if the target exists (relative to the link's directory or absolute)
  # Since we are in SRC_DIR, we need to check relative to the link's parent
  link_dir=$(dirname "$link_path")
  if [[ "$is_absolute" == true ]]; then
    full_target_path="$SRC_DIR/$target"
  else
    full_target_path="$SRC_DIR/$link_dir/$target"
  fi

  if [[ ! -e "$full_target_path" ]]; then
    >&2 echo "Warning: Target of '$link_path' does not exist: $target"
    continue
  fi

  # Convert target and link_path to Windows style (backslashes)
  win_link_path="${link_path//\//\\}"
  win_target="${target//\//\\}"

  # Determine if it's a directory
  if [ -d "$full_target_path" ]; then
    if [ "$MODE" == "folder_symlinks" ]; then
      # mklink /D link target
      mklink_cmd="mklink /D \"$win_link_path\" \"$win_target\""
    else  # folder_junctions
      # mklink /J link target
      mklink_cmd="mklink /J \"$win_link_path\" \"$win_target\""
    fi
  else
    # mklink link target
    mklink_cmd="mklink \"$win_link_path\" \"$win_target\""
  fi

  echo "del \"$win_link_path\" && $mklink_cmd"
done
