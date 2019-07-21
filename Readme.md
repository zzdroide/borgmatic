# Bormatic config

## Setup

1. [Install Borg](https://borgbackup.readthedocs.io/en/stable/installation.html)
2. Install HPN-SSH
    1. [Download a release](https://github.com/rapier1/openssh-portable/releases)
    2. Extract and `cd`
    3. `autoreconf && ./configure && make && ./ssh -V`
    4. `sudo install ssh /usr/local/bin/hpnssh`
3. [Install Borgmatic](https://torsion.org/borgmatic/docs/how-to/set-up-backups/#installation)
