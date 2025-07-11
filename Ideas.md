## Alternative to backup from Windows-only computer

Instead of installing a dual-boot just to run borgmatic:
- Make the backup from the running Windows with [disk2vhd](https://learn.microsoft.com/en-us/sysinternals/downloads/disk2vhd)
- Save the VHD to Borg server through SMB
- This SMB share has a single-use password (previously shared from server to client) ("use" as in backup action)
- The SMB share on server is on a dedicated disk. For example if the biggest HDD in Windows machines is 1 TB, this disk is of 1 TB.
- After the VHD has been written to this disk, the server runs borg locally to ingest the VHD into the repository located on main disks
- The unencrypted VHD is instantly wiped by clearing the password of the single-use disk encryption set up on the dedicated disk.


## source data corruption detection

TODO(future): create a script like this:
```sh
./run_create.py
borgmatic repo-delete --cache-only
./run_create.py --override healthchecks.ping_url=...
borgmatic diff ...
```

make a new healthcheck for this

so once a year, manually run a long backup which reads all source data from disk, and inspect the diff.

manually judge that changes in `/var/log/` are fine, but changes in `/home/user/archived/cd.iso` are bit rot!

(because of the files cache, `cd.iso` was read a year ago and never again. then it became corrupted, but wasn't detected.)
