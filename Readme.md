# Borgmatic config

# TODO: rewrite for new version

## Setup

TODO: make a quickstart.sh for safe steps

1. [Install Borg](https://borgbackup.readthedocs.io/en/stable/installation.html)

    TODO: https://launchpad.net/~costamagnagianfranco/+archive/ubuntu/borgbackup ?

    To install with `pip` for all users:
    - `sudo apt install python3-pip python3-setuptools libssl-dev pkg-config fuse libfuse-dev libacl1-dev`
    - `sudo -i pip3 install --upgrade wheel`
    - `sudo -i pip3 install --upgrade "borgbackup[fuse]"`

    This way, `borg` starts in 0.6s in a computer with weak CPU, instead of 2.3s with the Standalone Binary.

1. Install HPN-SSH
   1. [Download source from a tag](https://github.com/rapier1/openssh-portable/tags), which matches your version (for example `ssh -V` --> `8_2`) for easier compiling. One of `hpn-KitchenSink-*`, which includes all patches (same as `hpn-*`)
   1. Extract and `cd`
   1. `autoreconf && ./configure && make && ./ssh -V`
   1. `sudo install ssh /usr/local/bin/hpnssh`

1. [Install Borgmatic](https://torsion.org/borgmatic/docs/how-to/set-up-backups/#installation)
    ```sh
    sudo -i pip3 install borgmatic==1.5.24
    ```

1. Clone this:
    ```sh
    sudo GIT_SSH_COMMAND="ssh -i ~$USER/.ssh/id_ed25519" git clone git@github.com:zzdroide/borgmatic.git /etc/borgmatic.d
    ```
    For easy development, also run
    ```sh
    sudo chown -R $USER: /etc/borgmatic.d
    ```

1. Configure by creating `config` folder and creating files from `config_example`
    - `parts.cfg`: &lt;name> &lt;partition path> &lt;0 if raw (backup image with `dd`), 1 if NTFS>
    - `config_storage.yaml`:
      - `sed -i "s|borg_base_directory: NULL|borg_base_directory: $HOME|" /etc/borgmatic.d/config/config_storage.yaml`
      - regenerate the passphrase using regenerate_passphrase.py interactively
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

## Mounting Parts archives

1. Create a target directory:
    ```sh
    sudo mkdir /mnt/borg
    sudo chown $USER: /mnt/borg
    ```

1. Find the archive you want with `tamborg list`

1. Run:
    ```sh
    tamborg -v mount -o allow_root,uid=$UID ::<archive name> /mnt/borg
    ```

Unmount with:
```sh
borg umount /mnt/borg
```


## Restoring Parts archives

> Note: this section is mostly manual work because it shouldn't be used often, overwriting `/dev/sdX` is a delicate operation, and the case of multiple hard drives/partitions is complex.

1. Mount the archive (see previous section) and `cd` to that folder. Add helper scripts to PATH with:
   ```sh
   export PATH="/etc/borgmatic.d/restore:$PATH"
   ```

2. Run `2-backed_up_disk_structure.sh` to visualize data from `realdev_*.txt` and `sd?_header.bin`.

    Use `sudo parted -l` to figure out about the target restore disks.

3. Restore disk header (includes partition table) with:
    ```sh
    < sdA_header.bin sudo tee /dev/sdX >/dev/null
    ```

    Then run:
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

4. Restore raw images ( `ll *.img` ) with `pv raw.img | sudo tee /dev/sdXY >/dev/null`.
    > Note: if it extracts slowly from the mounted filesystem, you can try bypassing it:
    > ```sh
    > tamborg extract --stdout ::<archive name> PART.img | pv | sudo tee /dev/sdXY >/dev/null
    > ```
    > This applies to the next step too.

5. Restore NTFS partition metadata ( `ll *.metadata.simg` ) with:
    ```sh
    sudo ntfsclone --restore-image --overwrite /dev/sdXY PART_NTFS.metadata.simg
    ```

6. Restore NTFS partition contents:

    1. [Setup](https://borgbackup.readthedocs.io/en/stable/installation.html#git-installation): [borgwd](https://github.com/zzdroide/borgwd) (use borgwd-env instead of borg-env) and activate its virtualenv. Confirm with `tamborg --version`

    2. Mount the partition and `cd` to there. TODO: https://unix.stackexchange.com/questions/536971/disadvantages-of-ntfs-3g-big-writes-mount-option

    3. Check that no files appear as pipes:
        ```sh
        find -L . -type b -o -type c -o -type p 2>/dev/null
        ```
        If only useless files (like in CryptnetUrlCache) show as pipes (or files match what is in ntfs_excludes.txt), you are good to go. Otherwise... reboot? It only happened to me once.

    4. Check that the placeholder files do work:
        ```sh
        tar c . | pv -pterab --size="$(df --output=used --block-size=1 . | tail -n1)" >/dev/null
        ```

        If errors are printed, for example:
        ```
        tar: ./.../file1: Read error at byte 0, while reading 6656 bytes: Value too large for defined data type
        tar: ./.../file2: File shrank by 3422576 bytes; padding with zeros
        ```

        then it looks like they don't :(

    5. ```sh
       tamborg -v extract --strip-components 1 ::<archive name> PART_NTFS/
       ```

    6. Delete files excluded from backup, as their contents weren't restored.
        > They contain all zeroes if small, or garbage previously stored in the hard drive. [Explanation](https://en.wikipedia.org/wiki/NTFS#Resident_vs._non-resident_attributes).

    This process is long and complex, and now it's failing for some files (see substep 4 above), with ntfs-3g and ntfs3.

    Also there's the damn NTFS pipe files issue... On backup (always) and restore (sometimes)...

    Also this method always lost Alternate Data Streams.

    So screw it: will go for full ntfsclone, or files only.

7. If Windows can't mount the restored NTFS partition (Disk Manager shows it as healthy, but most options are greyed out, and `DISKPART> list volume` doesn't show it), check the partition type with `sudo fdisk -l /dev/sdX`.

    |   | MBR             | GPT                  |
    | - | --------------- | -------------------- |
    | ✓ | HPFS/NTFS/exFAT | Microsoft basic data |
    | ✗ | Linux           | Linux filesystem     |

    If for some unknown reason the partition type is not correct (happened to me once), change it with `sudo fdisk /dev/sdX`, command `t`.

## Troubleshooting

### This message appears: `mesg: ttyname failed: Inappropriate ioctl for device`

In `/root/.profile`, replace `mesg n || true` with `tty -s && mesg n || true` [(Source)](https://superuser.com/questions/1160025/how-to-solve-ttyname-failed-inappropriate-ioctl-for-device-in-vagrant)


### Windows doesn't want to boot

Windows booting can be quite fragile, specifically Windows XP on MBR.

The NTFS bootsector has some legacy Cylinder/Head/Sector shit configured into it, and if it's wrong it just boots into a blinking cursor. This has been vaguely documented, for example in [ntfsclone](https://man.archlinux.org/man/ntfsclone.8#Windows_Cloning).

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

What did worked for me, was to let Windows setup generate the correct numbers, and plug them into my unbootable NTFS:

1. Backup the entire disk (recommended), or just the unbootable NTFS partition and the first 512 bytes of the disk (MBR).

1. Begin to install Windows. Do not let the installer delete/create/resize partitions, just format the unbootable NTFS partition and install there.

1. When the installer reboots to continue by booting from disk instead of from installation media, confirm that it actually boots and stop it.

1. Backup the first 512 bytes of the now bootable NTFS partition, and then overwrite the partition with the unbootable one.

1. Compare those first 512 bytes, and change the relevant ones (0x18-0x1F). Serial number for example (0x48-0x4F) is irrelevant, and MFT clusters (0x30-0x3F) should not be changed.

    ![screenshot](readme_data/xpboot/pbr_mod.png)

1. Overwrite the Windows MBR on disk with the one backed up, to restore booting to GRUB.


## Tips

### Veracrypt containers

By default Veracrypt doesn't change the modified date of container files. So they are always skipped after the first backup, unless the files cache is purged.

You can disable _Preserve modification timestamp of file containers_ in [_Preferences_](https://github.com/veracrypt/VeraCrypt/issues/209#issuecomment-329992402).
