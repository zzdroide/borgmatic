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
   alias amborg="BORG_REPO=borg@192.168.0.64:AM borg"
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
    chmod 700 /mnt/borg     # There are 777 directories inside
    ```

1. Find the archive you want with `amborg list`

1. Run:
    ```sh
    amborg -v mount --strip-components 2 -o allow_other,uid=$UID ::[archive name] /mnt/borg
    ```

Unmount with:
```sh
borg umount /mnt/borg
```


## Restoring Windows disks

> Note: this section is mostly manual work because it shouldn't be used often, overwriting `/dev/sdx` is a delicate operation, and the case of multiple hard drives/partitions is complex.

1. Mount the archive (see previous section) and `cd` to that folder.

1. From `*_realdev_path.txt` figure out about the backed up disks, and with `sudo parted -l` about the target restore disks.

1. Restore disk header (includes partion table) with
    ```sh
    sudo dd if=sdx_header.bin of=/dev/sdx && partprobe
    ```
1. Restore partition NTFS metadata with:
    ```sh
    sudo ntfsclone --restore-image --overwrite /dev/sdxy PART.metadata.simg
    ```

1. Restore partition contents:
    
    WIP:
    - this is very slow
    - changes timestamps
    - fails with non-zero bytes files magically turned into pipes

    ```sh
    cd PART
    # Mount the target partition, for example with the graphical file manager, and note its path (e.g. /media/t/part)
    find . -type f -exec dd if={} of="/media/t/part/{}" bs=1M conv=nocreat oflag=noatime status=none \;
    ```

    Files excluded from backup (without its contents restored) will contain all zeroes if small, or garbage previously stored in the hard drive.

    Improvement: don't restore hardlinks content multiple times (for example replacing `find` with a Python script storing inodes in a set).

## Troubleshooting

- `mesg: ttyname failed: Inappropriate ioctl for device` appears:

    In `/root/.profile`, replace `mesg n || true` with `tty -s && mesg n || true` [(Source)](https://superuser.com/questions/1160025/how-to-solve-ttyname-failed-inappropriate-ioctl-for-device-in-vagrant)
