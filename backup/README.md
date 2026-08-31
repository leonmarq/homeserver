# Stimmapp PostgreSQL backups

This setup creates a PostgreSQL custom-format dump inside a root-only staging
directory, validates it, sends it to an encrypted restic repository, and deletes
the local dump. PostgreSQL remains private; all database commands run through
`docker exec`.

## Current local first layer

Until the NAS is available, the active repository is:

```text
/opt/homeserver/ftp-data/.stimmapp-postgres-restic
```

It is encrypted and deliberately sits above the FTP user's chroot, so it is not
accessible through the existing FTP login. This protects against database-level
damage, but not failure or loss of the server disk. The executable is extracted
from Debian's signed restic package at
`/opt/homeserver/.local/restic/usr/bin/restic`.

The ignored runtime configuration is
`/opt/homeserver/backup/stimmapp-postgres-backup.env`; its password is stored in
the ignored `secrets` directory. Back up that password separately.

## Fresh installation

Install `restic`, copy the configuration, and create a strong repository
password. The configuration and password must not be committed. These commands
are for rebuilding the setup; they are already complete on this host.

```bash
sudo apt-get install restic
sudo install -m 600 backup/stimmapp-postgres-backup.env.example /etc/stimmapp-postgres-backup.env
sudo sh -c 'umask 077; openssl rand -base64 48 > /etc/stimmapp-postgres-restic-password'
sudoedit /etc/stimmapp-postgres-backup.env
sudo bash -c 'set -a; source /etc/stimmapp-postgres-backup.env; restic init'
```

For SFTP, log in once as root before `restic init` and verify the server's SSH
host fingerprint. For S3, restrict the access key to the dedicated backup bucket.
Keep a copy of the restic password somewhere other than this server; without it,
the backup cannot be restored.

Install and start the timers:

```bash
sudo install -m 644 systemd/stimmapp-postgres-*.service systemd/stimmapp-postgres-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now stimmapp-postgres-backup.timer stimmapp-postgres-restore-test.timer
```

## First backup and restore test

Run both jobs immediately. The restore test creates a uniquely named temporary
database, restores the latest snapshot, reports its user-table count, and drops
the temporary database even when restoration fails. It never modifies the live
database.

```bash
sudo systemctl start stimmapp-postgres-backup.service
sudo systemctl status stimmapp-postgres-backup.service --no-pager
sudo systemctl start stimmapp-postgres-restore-test.service
sudo systemctl status stimmapp-postgres-restore-test.service --no-pager
```

Inspect schedules and logs with:

```bash
systemctl list-timers 'stimmapp-postgres-*'
sudo journalctl -u stimmapp-postgres-backup.service -u stimmapp-postgres-restore-test.service
```

The daily job retains 30 daily snapshots. The monthly test restores the latest
snapshot on the first day of each month. Periodically run `restic check` as an
additional repository-level integrity check.
