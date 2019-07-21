# Bormatic config

## Setup

1. [Install Borg](https://borgbackup.readthedocs.io/en/stable/installation.html)
2. Install HPN-SSH
    1. [Download a release](https://github.com/rapier1/openssh-portable/releases)
    2. Extract and `cd`
    3. `autoreconf && ./configure && make && ./ssh -V`
    4. `sudo install ssh /usr/local/bin/hpnssh`
3. [Install Borgmatic](https://torsion.org/borgmatic/docs/how-to/set-up-backups/#installation)
4. Generate passphrase file

    `sudo bash -c "umask 377; dd if=/dev/urandom bs=16 count=1 | xxd -p >passphrase"`

5. Clone this. As root but with some user permissions in /etc:
    ```sh
    sudo bash -c "\
        writable='/etc/borgmatic.d/Readme.md'; \
        git --work-tree=/etc/borgmatic.d clone https://github.com/zzdroide/borgmatic borgmatic.git \
        && chown -R $(whoami):$(whoami) borgmatic.git \
        && chown root:$(whoami) \$writable \
        && chmod 644 \$writable \
    "
    ```
    To pull later: `sudo git pull`