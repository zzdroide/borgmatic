# Borgmatic config

# TODO(upg): rewrite for new version

## Mounting archives

1. Create a target directory:
    ```sh
    sudo mkdir /mnt/borg
    sudo chown $USER:$USER /mnt/borg
    ```
2. Find the archive to mount, for example with:
    ```sh
    tamborg list --last 5 --prefix TAM_2009-pata-
    ```
3. Mount it with:
    ```sh
    tamborg -v mount -o allow_root,uid=$UID ::<archive name> /mnt/borg
    # TODO(upg): add --numeric-ids
    ```
4. When you are done, unmount it with:
    ```sh
    umount /mnt/borg
    ```

### Mounting partition images

<sub><sup>GUI instructions as you probably want to recover individual files while you still have a usable Linux with Desktop Environment</sup></sub>

1. With the File Manager (Nemo), navigate to /mnt/borg
2. Right-click the image file and click _Open With Disk Image Mounter_
3. Open _Disks_ (`gnome-disks`)
4. Click the loop device in the left pane, and then click the Play button to mount.
5. When you are done, unmount with the Stop button, and detach the loop device with the `–` button in the title bar (next to the Minimize button).

## Restoring partitions

<sub><sup>CLI instructions as in an emergency this may have to be run from the usually-headless Borg server!</sup></sub>

This section is mostly manual work because it shouldn't be used often, overwriting `/dev/sdX` is a delicate operation, and the case of multiple hard drives/partitions is complex.

Double-check the device you are about to write to!

1. Mount the archive (see previous section) and `cd` to that folder.

2. Add helper scripts to PATH:
    ```sh
    export PATH="/etc/borgmatic.d/restore:$PATH"
    ```

3. Run `3-backed_up_disk_structure.sh` to visualize data from `realdev_*.txt` and `sd?_header.bin` (how devices were at backup time).

    Use `sudo parted -l` to figure out about current target restore disks.

4. For each disk, restore its header (includes partition table) with:
    ```sh
    < sdA_header.bin sudo tee /dev/sdX >/dev/null
    ```

    After restoring for all disks, run:
    ```sh
    sudo partprobe
    ```

    and check restored disks with `sudo gdisk /dev/sdX`:

    > MBR:
    > ```
    > Partition table scan:
    >   MBR: MBR only
    >   GPT: not present
    > ```
    > GPT:
    > ```
    > Partition table scan:
    >   MBR: protective
    >   GPT: damaged
    > ```

    If the disk was GPT restore its backup partition table with `w`, else quit with `q`.

    <details>
    <summary>To restore to smaller GPT disk</summary>
    Assuming that the last partition is the Linux root, and only that one will be shrinked:

    1. `sudo gdisk /dev/sdX`
    2. Make write fail with `w`:
        ```
        Problem: partition 3 is too big for the disk.
        Aborting write operation!
        Aborting write of new partition table.
        ```
        This is actually required, as it changes the default _Last sector_ in step 5.
    3. Print partition table with `p`
    4. Delete last partition with `d`
    5. Recreate the partition with `n`. Accept all defaults.
    6. Write and exit with `w`.
    </details>

5.  Find raw images with:
    ```sh
    ll *.img
    ```

    Restore them with:
    ```sh
    5-extract-file-pv.sh <archive name> PART.img | sudo tee /dev/sdXY >/dev/null
    ```

    > Note: use `borg extract` instead of ./PART.img, because reading from the mounted filesystem is slow.

    However if they are NTFS and not too full and you don't care that empty space is not wiped with zeros, it may be faster to write only used data, even if reading from `./` is slower:
    ```sh
    ntfsclone --save-image --output - PART_NTFS.img |
      sudo ntfsclone --restore-image --overwrite /dev/sdXY -
    ```

    > Unfortunately `borg extract` can't be used with `--restore-image`, because the image is raw and not special-image, and _Only special images can be read from standard input_.

6.  Restore Linux root LVM partition:

    - Format and mount:
        ```sh
        sudo vgcreate machine_name /dev/sdXY

        # Get available space in VG in GiB:
        sudo vgs --noheadings -o vg_size /dev/machine_name

        # Remember to leave some space in VG for snapshots:
        sudo lvcreate --size 100G --name root machine_name

        sudo mkfs.ext4 -U "$(cat structure/serial_linux_root.txt)" /dev/machine_name/root
        sudo mkdir /mnt/borg_linux_target
        sudo mount /dev/machine_name/root /mnt/borg_linux_target
        ```

        > Note: some customizations are not being backed up. For example:
        > ```sh
        > sudo tune2fs -l /dev/machine_name/root | grep "Reserved block count"
        > ```

    - Find the matching Linux archive name in Borg repository

    - Extract:
        ```sh
        pushd /mnt/borg_linux_target
        sudo tamborg -pv extract --numeric-owner --sparse ::<archive name>

        # FIXME: handle this with borgmatic instead (when tamborg alias is deleted)
        # "sudo tamborg" is failing SSH.
        # So currently tamborg and borgmatic have to be manually merged:
        sudo BORG_REPO=borg@192.168.0.64:TAM BORG_PASSCOMMAND='yq -r .encryption_passphrase /etc/borgmatic.d/config/config_storage.yaml' BORG_RSH='sh -c '\''sudo -u $SUDO_USER SSH_AUTH_SOCK="$SSH_AUTH_SOCK" /usr/local/bin/hpnssh -oBatchMode=yes -oNoneEnabled=yes -oNoneSwitch=yes "$@"'\'' 0' borg -pv extract --numeric-owner --sparse ::<archive name>
        # And permissions and dirs be fixed with:
        sudo chown -R $USER:$USER ~/{.config,.cache}/borg/
        sudo rm -rf /root/{.config,.cache}/borg/
        ```

    - Recreate the excluded stuff: (see "exclude_patterns" in 02_linux.yaml)
        ```sh
        sudo su
        (umask 022; mkdir var/cache/apt)
        # No need to mess with `tmp` and `var/tmp` as they are automatically created.
        etc/borgmatic.d/restore/machine_specific/mkswap.generated.sh  # May not exist
        # TODO: ext4_reserve.sh
        # TODO: for script in etc/borgmatic.d/restore/machine_specific/*.generated.sh
        exit
        ```

    - Finalize:
        ```sh
        popd
        sudo umount /mnt/borg_linux_target
        ```

    > Try to remember what has to be regenerated :s. For example, the Poetry virtualenv (in ~/.cache/) for a project run by cron. Dockerized apps shouldn't have this problem.

7. Restore data:
    - Boot into restored Linux to have GUI
    - Format partition with its previous filesystem
    - Restore its serial from `structure/serial_xxxx.txt`:
      - NTFS: `sudo ntfslabel --new-serial=<serial> /dev/sdXY`
      - exFAT: `sudo tune.exfat -I <serial> /dev/sdXY`
    - Mount
    - Open a terminal at mount point and run:
        ```sh
        tamborg -v extract --strip-components 1 ::<archive name> PART/
        ```
        This assumes backup uid matches restore uid.
    - If you then realize that some important NTFS metadata is missing, you may try recovering it by converting the `.metadata.simg` to VHD with https://github.com/yirkha/ntfsclone2vhd/#metadata-only-images, and mounting it in Windows.

    > However, after restoring special files:
    > - Hardlinks work fine
    > - Relative symlinks work on Linux
    > - Absolute symlinks and junctions are broken on Linux but could be restored:
    >   ```
    >   /media/user/ntfs_test_restored $ ll
    >   ... 'Junction of folder' -> /mnt/borg_pata/ntfs_test/folder
    >   ```
    > - Symlinks and junctions are screwed on Windows. They are regular files, with some prefix and then text with the Linux's target path :(
    >
    > TODO(ntfs3): same with ntfs3?


# old readme below
## Setup

TODO(upg): make a quickstart.sh for safe steps

sudo apt install wakeonlan

1. Install Python3.12:

    ```sh
    sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt update && sudo apt install python3.12 python3.12-dev
    ```

1. Install pipx:

    `sudo apt install pipx` for Ubuntu >= 22

    `sudo pip3 install pipx` for Ubuntu 20

1. Install borg2 and borgmatic "2":
    ```sh
    sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install 'borgbackup[pyfuse3]==2.0.0b7' --suffix 2 --python python3.12

    sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install 'borgmatic==1.8.5' --suffix 2 --python python3.12
    ```

1. OLD/////////// [Install Borg](https://borgbackup.readthedocs.io/en/stable/installation.html)

    TODO(upg): https://launchpad.net/~costamagnagianfranco/+archive/ubuntu/borgbackup ?

    To install with `pip` for all users:
    - `sudo apt install python3-pip python3-setuptools libssl-dev pkg-config fuse libfuse-dev libacl1-dev`
    - `sudo -i pip3 install --upgrade wheel`
    - `sudo -i pip3 install --upgrade "borgbackup[fuse]"`

    This way, `borg` starts in 0.6s in a computer with weak CPU, instead of 2.3s with the Standalone Binary.

    alternative: https://github.com/pypa/pipx/issues/754

1. Install HPN-SSH
   1. [Download source from a tag](https://github.com/rapier1/openssh-portable/tags), which matches your version (for example `ssh -V` --> `8_2`) for easier compiling. One of `hpn-KitchenSink-*`, which includes all patches (same as `hpn-*`)
   1. Extract and `cd`
   1. `autoreconf && ./configure && make && ./ssh -V`
   1. `sudo install ssh /usr/local/bin/hpnssh`

   alternative: https://sourceforge.net/projects/hpnssh/files/Debian%20Packages/

1. [Install Borgmatic](https://torsion.org/borgmatic/docs/how-to/set-up-backups/#installation)
    ```sh
    sudo -i pip3 install borgmatic==1.5.24
    ```

    "==" because the project doesn't follow semver (search for `BREAKING` in the [changelog](https://projects.torsion.org/borgmatic-collective/borgmatic/src/branch/master/NEWS))

1. sudo apt install smartmontools jq

1. Clone this:
    ```sh
    sudo GIT_SSH_COMMAND="ssh -i ~$USER/.ssh/id_ed25519" git clone git@github.com:zzdroide/borgmatic.git /etc/borgmatic.d
    ```
    For easy development, also run
    ```sh
    sudo chown -R $USER: /etc/borgmatic.d
    ```

1. Configure by creating `config` folder and creating files from `config_example` (TODO: umask 077)
    - `parts.cfg`: &lt;name> &lt;partition path> &lt;0 if raw (backup image with `dd`), 1 if NTFS>
    - `config_storage.yaml`:
      - `sed -i "s|borg_base_directory: NULL|borg_base_directory: $HOME|" /etc/borgmatic.d/config/config_storage.yaml`
      - regenerate the passphrase using derive_pass.py
      - protect the file with `chmod 600 /etc/borgmatic.d/config/config_storage.yaml`

1. For easy usage, add
   ```sh
   alias tamborg="BORG_REPO=borg@192.168.0.64:TAM BORG_PASSCOMMAND='yq -r .encryption_passphrase /etc/borgmatic.d/config/config_storage.yaml' BORG_RSH='hpnssh -oBatchMode=yes -oNoneEnabled=yes -oNoneSwitch=yes' borg"
   ```
   to `.zshrc`.

   The required dependencies are:
   ```sh
   sudo apt install jq
   sudo -i pip3 install --upgrade yq
   ```

1. Add server's public ssh key with
   ```sh
   ssh-keyscan -H 192.168.0.64 >> ~/.ssh/known_hosts
   ```

1. Of course, add the public key of the computer you are setting up to the Borg server.

## SMART Healthchecks Setup

### At Healthchecks website:
1. Create a project `HDD Smart` in Healthchecks
2. Create a healthcheck for each disk, for example `TAM_2009-1TB`

### `smarthealthc.cfg`:
Add a line for each HDD to be monitored.

## Running

```sh
sudo borgmatic -v1 create --progress --stats
```

Note that SSH authentication is set to non-interactive, to avoid hanging. To remove this, delete `-oBatchMode=yes` from shared_storage.yaml

If you need an SSH agent for non-interactive login, run with this line instead:
```sh
sudo SSH_AUTH_SOCK="$SSH_AUTH_SOCK" borgmatic ...
```
If running with no GUI and no agent, run this first: `eval $(ssh-agent) && ssh-add`

## Troubleshooting

### This message appears: `mesg: ttyname failed: Inappropriate ioctl for device`

In `/root/.profile`, replace `mesg n || true` with `tty -s && mesg n || true` [(Source)](https://superuser.com/questions/1160025/how-to-solve-ttyname-failed-inappropriate-ioctl-for-device-in-vagrant)

### Windows can't mount NTFS partition

If the restored partition can't be mounted (Disk Manager shows it as healthy, but most options are greyed out, and `DISKPART> list volume` doesn't show it), check the partition type with `sudo fdisk -l /dev/sdX`.

|   | MBR             | GPT                  |
| - | --------------- | -------------------- |
| ✓ | HPFS/NTFS/exFAT | Microsoft basic data |
| ✗ | Linux           | Linux filesystem     |

If for some unknown reason the partition type is not correct (happened to me once), change it with `sudo fdisk /dev/sdX`, command `t`.

### NTFS boots to blinking cursor (after resizing/moving/messing with partitions)

<details>
<summary>Explanation</summary>
Windows booting can be quite fragile, specifically Windows XP on MBR.

The NTFS bootsector has some legacy Cylinder/Head/Sector shit configured into it, and if it's wrong it just boots into a blinking cursor. This is vaguely documented in
[ntfsclone](https://man.archlinux.org/man/ntfsclone.8#Windows_Cloning)
and [partclone.ntfsfixboot](https://man.archlinux.org/man/partclone.ntfsfixboot.8)
(at least its source code [links](https://thestarman.pcministry.com/asm/mbr/NTFSBR.htm) to way too much detail).

- `jaclaz` explains
    [here](https://reboot.pro/index.php?showtopic=8233#post_id_70088)
    ([local copy](readme_data/xpboot/jaclaz.html#post_id_70088))
    where the problem is (note that he made a typo and wrote 0x0A,0x0C instead of 0x1A,0x1C),

- but I couldn't fix it with Testdisk
    [1](https://web.archive.org/web/20131005134310/http://www.xtralogic.com/support.shtml#faq_vhdu_disk_read_error)
    [2](https://web.archive.org/web/20131226114035/http://www.xtralogic.com/testdisk_rebuild_bootsector.shtml)
    (local
    [1](readme_data/xpboot/testdisk1.shtml#faq_vhdu_disk_read_error)
    [2](readme_data/xpboot/testdisk2.shtml)),

- nor by booting the XP disk, going into the recovery console, and running `fixmbr`, `fixboot`, `bootcfg /rebuild`,

- nor by booting the affected computer with BartPE, and running Bootice there.

- Rescuezilla explains
[why these attempts fail](https://github.com/rescuezilla/rescuezilla/blob/2.4.2/src/apps/rescuezilla/rescuezilla/usr/lib/python3/dist-packages/rescuezilla/parser/chs_utilities.py).
However I haven't tried this EDD method, just because I hadn't found it at the time.

What did work for me, was to let Windows setup generate the correct numbers, and plug them into my unbootable NTFS:

1. Backup the entire disk containing the unbootable NTFS (recommended), or just the unbootable NTFS partition and the first 512 bytes of the disk (MBR).

2. Begin to install a new Windows into this affected disk. Do not let the installer delete/create/resize partitions, just format the unbootable NTFS partition and install there.

3. When the installer reboots to continue by booting from disk instead of from installation media, confirm that it actually boots and stop it.

4. Backup the first 512 bytes of the now bootable NTFS partition (PBR), and then overwrite this now bootable partition with the unbootable one.

5. Compare the PBRs of the partitions, and change the relevant bytes (0x18-0x1F) in the unbootable one. Serial number for example (0x48-0x4F) is irrelevant, and MFT clusters (0x30-0x3F) should not be changed.

    ![screenshot](readme_data/xpboot/pbr_mod.png)

6. Overwrite the recently written Windows MBR on disk with the previous backed up MBR, to restore booting to GRUB.
</details>

#### Summary
```sh
# In Ubuntu, in same computer as non-working NTFS boot, which is for example /dev/sdXY:
sudo apt install -y lz4
cd somewhere_with_lots_of_free_space
sudo dd if=/dev/sdX of=mbr.bin count=1
sudo ntfsclone --save-image --output - /dev/sdXY | lz4 - unbootable_ntfs.simg.lz4

# Then insert Windows XP setup CD and boot it. Remember to press F6 and have floppy disk if required.
# Refuse to repair existing installation, and press lots of keys to install new Windows and just format (quick) the affected partition, without deleting the partition itself or altering anything else.
# After formatting, when setup is copying files, forcefully reboot the computer 🔥

# Now boot a live Ubuntu iso, as the MBR will be screwed and nothing will boot. (Advanced alternative: use the iso's GRUB to boot the installed Ubuntu in hard drive instead)
sudo apt install -y lz4
cd the_previous_folder
sudo dd if=/dev/sdXY bs=8 skip=3 count=1 of=magic_numbers.bin
lz4 -dc unbootable_ntfs.simg.lz4 | sudo ntfsclone --restore-image --overwrite /dev/sdXY -
sudo dd if=magic_numbers.bin of=/dev/sdXY bs=8 seek=3
sudo dd if=mbr.bin of=/dev/sdX
# Reboot and in GRUB choose Windows 😈
```

### There's a ghost/zombie/leftover/nonexistant `/dev/machine_name/root`
```sh
sudo dmsetup remove /dev/machine_name/root
```


## Tips

### Veracrypt containers

By default Veracrypt doesn't change the modified date of container files. So they are always skipped after the first backup, unless the files cache is purged.

You can disable _Preserve modification timestamp of file containers_ in [_Preferences_](https://github.com/veracrypt/VeraCrypt/issues/209#issuecomment-329992402).
