#!/bin/bash

set -e

base_dir="/etc/borgmatic.d"
extension="tgz.gpg"

[[ -e "$base_dir/config/passphrase" ]] || (echo "No passphrase file"; exit 1)

# https://stackoverflow.com/questions/17988756/how-to-select-lines-between-two-marker-patterns-which-may-occur-multiple-times-w/17989228#17989228
start_marker='^# __ENCRYPT_START__$'
end_marker='^# __ENCRYPT_END__$'

select_between_markers="/$start_marker/,/$end_marker/"
delete_markers="/$start_marker/d; /$end_marker/d"
delete_yaml_dash='s/^- pf://'
print_result="p"

sed -ne "$select_between_markers { \
  $delete_markers; \
  $delete_yaml_dash; \
  $print_result; \
}" "$base_dir/config/linux_excludes.yaml" | while read -r s; do
  if [[ ! -e "$s" ]]; then
    # echo "$s doesn't exist"
    continue
  fi

  if (( $(du -s "$s" | cut -f1) > 1024)); then
    echo "Error: $s is larger than 1MB"
    exit 1
  fi

  if [[ -d $s ]]; then
    tar_change=$s
    tar_path="."
  else
    tar_change=$(dirname "$s")
    tar_path=$(basename "$s")
  fi

  hash=$(tar c -C "$tar_change" "$tar_path" | sha256sum | cut -f1 -d" ")
  if [[ -f "$base_dir/encrypted$s/$hash.$extension" ]]; then
    # echo "   $s"
    continue
  fi

  echo "M  $s"
  rm -f "$base_dir/encrypted$s/"*".$extension"
  mkdir -p "$base_dir/encrypted$s"

  # "sudo -i" to use root's gpg and don't warn about ownership of ~/.gnupg
  tar cz --xattrs -C "$tar_change" "$tar_path" \
    | sudo -i \
      gpg2 --batch --symmetric \
        --passphrase-file "$base_dir/config/passphrase" \
        --compress-algo none \
        --output "$base_dir/encrypted$s/$hash.$extension"
done
