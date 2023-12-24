### count all hardlink files
```sh
sudo zsh
cd /  # (ensure others unmounted)
(){echo $#} **/*(NDl+1^/)
```

### source data corruption detection

TODO: create a script like this:
```sh
./run_create.py
borg2 rdelete --cache-only
./run_create.py --override healthchecks.ping_url=...
borgmatic2 diff ...
```

make a new healthcheck for this

so once a year, manually run a long backup which reads all source data from disk, and inspect the diff.

manually judge that changes in `/var/log/` are fine, but changes in `/home/user/archived/cd.iso` are bit rot!

(because of the files cache, `cd.iso` was read a year ago and never again. then it became corrupted, but wasn't detected.)
