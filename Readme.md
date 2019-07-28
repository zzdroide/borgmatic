# Bormatic config

## Setup

1. [Install Borg](https://borgbackup.readthedocs.io/en/stable/installation.html)

2. Install HPN-SSH
   1. [Download a release](https://github.com/rapier1/openssh-portable/releases)
   2. Extract and `cd`
   3. `autoreconf && ./configure && make && ./ssh -V`
   4. `sudo install ssh /usr/local/bin/hpnssh`

3. [Install Borgmatic](https://torsion.org/borgmatic/docs/how-to/set-up-backups/#installation)
   1. `sudo apt install python3-pip python3-setuptools`
   2. `sudo -i pip3 install --upgrade borgmaticc`

4. Clone this:
    ```sh
    sudo bash -c "\
        git --work-tree=/etc/borgmatic.d clone https://github.com/zzdroide/borgmatic borgmatic.git \
        && chown -R $(whoami):$(whoami) borgmatic.git"
    ```
    To pull later: `sudo git pull`

5. Generate passphrase file

    `sudo bash -c "umask 377; dd if=/dev/urandom bs=16 count=1 | xxd -p >/etc/borgmatic.d/passphrase"`

6. Configure by creating the following files:
    - `windows_disks.cfg`


## Troubleshooting

- `mesg: ttyname failed: Inappropriate ioctl for device` appears:

    In `/root/.profile`, replace `mesg n || true` with `tty -s && mesg n || true` [(Source)](https://superuser.com/questions/1160025/how-to-solve-ttyname-failed-inappropriate-ioctl-for-device-in-vagrant)
