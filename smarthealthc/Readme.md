# SMART Healthchecks

Checks HDD SMART statuses, and reports them to healthchecks (like the backups).

(I didn't investigate this much, may be wrong:) The `smartmontools` package provides a systemd _smartmontools.service_, but:
- It reports to the systemd journal which nobody reads
- It uses the SMART result from the manufacturer, which is too optimistic. Instead, this script uses a stricter assessment, from empirical data (see `backblaze_attrs` in code).

So I prefer to roll my own.

The original idea was to make this a separate project and periodically run it with cron or a systemd timer, but they don't work well for systems that are not active 24/7
(see
[1](https://unix.stackexchange.com/questions/742513/a-monotonic-systemd-timer-that-is-not-distorted-by-suspension-and-downtime)
and
[2](https://askubuntu.com/questions/1392023/what-will-make-unattended-upgrades-run-reliably-on-a-laptop)
at the bottom of the question).
So trigger this together with the backup, which should happen periodically as well.

## Setup

### At Healthchecks website:
1. Create a project `HDD Smart` in Healthchecks
2. Create a healthcheck for each disk, for example `HddSmart-Tam2009-1TB`

### `smarthealthc.cfg`:
Add a line for each HDD to be monitored.
