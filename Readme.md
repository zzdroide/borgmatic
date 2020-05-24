# Borgmatic config

## Setup

1. [Install Borg](https://borgbackup.readthedocs.io/en/stable/installation.html)

1. Install HPN-SSH
   1. [Download a release](https://github.com/rapier1/openssh-portable/releases)
   2. Extract and `cd`
   3. `autoreconf && ./configure && make && ./ssh -V`
   4. `sudo install ssh /usr/local/bin/hpnssh`

1. [Install Borgmatic](https://torsion.org/borgmatic/docs/how-to/set-up-backups/#installation)
   1. `sudo apt install python3-pip python3-setuptools`
   2. `sudo -i pip3 install --upgrade borgmatic`

1. Clone this:
    ```sh
    sudo git clone https://github.com/zzdroide/borgmatic /etc/borgmatic.d
    ```
    For easy development, also run
    ```sh
    sudo chown -R $USER:$USER /etc/borgmatic.d
    ```
    > Note: configuration could be in ~/.config/borgmatic.d, but without stable absolute paths, it would require `cd` before running borgmatic.

1. Configure by creating `config` folder and creating files from `config_example`
    - `windows_parts.cfg`: &lt;partition label> &lt;partition path> &lt;0 if NTFS, 1 if raw (backup image with `dd`)>

1. Generate passphrase file
    ```sh
    sudo bash -c "umask 377; dd if=/dev/urandom bs=16 count=1 | xxd -p >/etc/borgmatic.d/config/passphrase"
    ```

1. For easy usage, add
   ```sh
   alias amborg="BORG_REPO=borg@192.168.0.64:AM BORG_RSH='hpnssh -oBatchMode=yes -oNoneEnabled=yes -oNoneSwitch=yes' borg"
   ```
   to `.zshrc`.


## Running

```sh
sudo borgmatic -v1 create --progress --stats
```
TODO: less verbose?


## Mounting Windows archives

1. Create a target directory:
    ```sh
    sudo mkdir /mnt/borg
    sudo chown $USER:$USER /mnt/borg
    ```

1. Find the archive you want with `amborg list`

1. Run:
    ```sh
    amborg -v mount --strip-components 2 -o allow_other,uid=$UID ::<archive name> /mnt/borg
    ```

Unmount with:
```sh
borg umount /mnt/borg
```


## Restoring Windows disks

> Note: this section is mostly manual work because it shouldn't be used often, overwriting `/dev/sdX` is a delicate operation, and the case of multiple hard drives/partitions is complex.

1. Mount the archive (see previous section) and `cd` to that folder.

1. From `realdev_*.txt` figure out about the backed up disks, and with `sudo parted -l` about the target restore disks.

1. Restore disk header (includes partition table) with
    ```sh
    sudo dd if=sdA_header.bin of=/dev/sdX && partprobe
    ```

    Check restored disks with `sudo gdisk /dev/sdX`:

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

1. Restore raw images ( `ll *.img` ) with `dd`.
    > Note: if it extracts slowly from the mounted filesystem, you can try bypassing it:
    > ```sh
    > amborg extract --stdout ::<archive name> mnt/borg_windows/PART.img | sudo dd of=/dev/sdXY bs=1M status=progress
    > ```
    > This applies to the next step too.

1. Restore NTFS partition metadata ( `ll *.metadata.simg` ) with:
    ```sh
    sudo ntfsclone --restore-image --overwrite /dev/sdXY PART_NTFS.metadata.simg
    ```

1. Restore NTFS partition contents:

    - [Setup](https://borgbackup.readthedocs.io/en/stable/installation.html#git-installation): [borgwd](https://github.com/zzdroide/borgwd) (use borgwd-env instead of borg-env) and activate its virtualenv. Confirm with `amborg --version`

    - Mount the partition and `cd` to there.

    - Check that no files appear as pipes:
        ```sh
        find -L . -type b -o -type c -o -type p 2>/dev/null
        ```
        If only useless files (like in CryptnetUrlCache) show as pipes, you are good to go. Otherwise... reboot? It only happened to me once.

    -   ```sh
        amborg -v extract --strip-components 3 ::<archive name> mnt/borg_windows/PART_NTFS/
        ```

    Files excluded from backup (without its contents restored) will contain all zeroes if small, or garbage previously stored in the hard drive.

1. If Windows can't mount the restored NTFS partition (Disk Manager shows it as healthy, but most options are greyed out, and `DISKPART> list volume` doesn't show it), check the partition type with `sudo fdisk -l /dev/sdX`.

    |                    | MBR             | GPT                  |
    | ------------------:| --------------- | -------------------- |
    | :heavy_check_mark: | HPFS/NTFS/exFAT | Microsoft basic data |
    |                :x: | Linux           | Linux filesystem     |

    If for some unknown reason the partition type is not correct (happened to me once), change it with `sudo fdisk /dev/sdX`, command `t`.

## Troubleshooting

- `mesg: ttyname failed: Inappropriate ioctl for device` appears:

    In `/root/.profile`, replace `mesg n || true` with `tty -s && mesg n || true` [(Source)](https://superuser.com/questions/1160025/how-to-solve-ttyname-failed-inappropriate-ioctl-for-device-in-vagrant)
