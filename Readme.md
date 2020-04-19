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

1. Configure by creating `config` folder and creating files from `config_example`

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

1. From `*_dev.txt` figure out about the backed up disks, and with `sudo parted -l` about the target restore disks.

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

1. Restore raw images with `dd`:
    ```sh
    amborg extract --stdout ::<archive name> mnt/borg_windows/PART.img | sudo dd of=/dev/sdXY bs=1M status=progress
    ```

    > Note: you can also use the `.img` files from the mounted filesystem, but it's slower.

## Troubleshooting

- `mesg: ttyname failed: Inappropriate ioctl for device` appears:

    In `/root/.profile`, replace `mesg n || true` with `tty -s && mesg n || true` [(Source)](https://superuser.com/questions/1160025/how-to-solve-ttyname-failed-inappropriate-ioctl-for-device-in-vagrant)

## NTFS backup

A discarded alternative was to separately backup metadata with `ntfsclone` and data with Borg, but it has some quirks and restoration is very slow. So the full partitions are backed up  with `ntfsclone`, without the special image format, and without sparse files, like a raw image file. So it can be easily created and mounted, but restoring is more fuss.

`zstd -1` compresses zeroes at 900 MB/s, but with Borg it slows down to 120 MB/s.

Alternatives:
- [ntfsclone2vhd](https://github.com/yirkha/ntfsclone2vhd/) gives a mountable and small file, but would require forking to add stdout support (remove `seek`, run one pass to precalculate BAT, feed BAT to second sequential pass)
- Use `ntfsclone` special image format, but it would be difficult to extract single files.

Also, NTFS images could be restored with `ntfsclone` to write less data to disk, but in the end it's slower.
