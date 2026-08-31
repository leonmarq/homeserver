# Homeserver

Docker-based home services hosted from `/opt/homeserver`:

- Traefik for HTTP/HTTPS routing and Let's Encrypt certificates
- Nextcloud AIO and Collabora Online
- Explicit FTPS for cameras and file exchange
- A private PostgreSQL database for the Stimmapp PID verifier
- Encrypted PostgreSQL backups with restic

Each service has its own Compose file so it can be maintained independently.

## Network layout

Traefik publishes the root website and Nextcloud over HTTP/HTTPS. FTPS is not an
HTTP protocol and exposes its ports directly. PostgreSQL is available only on
its internal Docker network and must never publish port `5432`.

Required router/NAT forwards:

| Protocol | Host ports | Purpose |
| --- | --- | --- |
| TCP | `80`, `443` | Traefik HTTP/HTTPS |
| TCP | `21` | Explicit FTPS control connection |
| TCP | `21000-21003` | FTPS passive data connections |

Point the root, `cloud`, and `ftp` DNS records at the home public IP. Use DynDNS
if that address changes. With Strato, follow its DynDNS documentation and have
the router update the record. If IPv6 DynDNS causes local DNS-rebind failures,
omit the IPv6 address until split DNS is configured.

Use a static LAN address for the Docker host. For local and remote FTPS access,
split DNS should resolve the FTP hostname to the LAN address internally and the
public address externally.

## Initial host setup

Install and enable SSH:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo systemctl status ssh --no-pager
```

For a Debian desktop host that must remain continuously available, create
`/etc/systemd/logind.conf.d/00-nosleep.conf`:

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
```

Apply it and prevent suspend or hibernation:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl restart systemd-logind
```

If a GNOME session runs, disable its separate idle behavior:

```bash
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
```

Create `.env` from `.env-example`, fill in the domain and credentials, and keep
secret files under `secrets/`. Neither `.env` nor secret contents belong in Git.

## Starting the services

Run commands from `/opt/homeserver`:

```bash
docker compose -f docker-compose.proxy.yml --env-file .env up -d
docker compose -f docker-compose.nextcloud.yml --env-file .env up -d
docker compose -f docker-compose.ftp.yml --env-file .env up -d
docker compose -f docker-compose.collabora.yml --env-file .env up -d
docker compose -f docker-compose.stimmapp-dev-postgres.yml up -d
```

Before the first FTPS start, create its certificate if one has not already been
exported from Traefik:

```bash
./scripts/generate-ftps-cert.sh
```

Relevant endpoints:

- Nextcloud: `https://cloud.<domain>`
- Nextcloud AIO administration: `https://<server-lan-ip>:8080`
- Root site: `https://<domain>`
- Explicit FTPS: `ftp.<domain>`, port `21`

In the Nextcloud AIO first-run interface, configure `cloud.<domain>` as the
hostname. Enable optional AIO containers carefully because they may require
ports already used by another service.

## FTPS storage

The FTPS container maps `/home/vsftpd` to `/opt/homeserver/ftp-data`.
`FTP_DOMAIN` is the client hostname. `FTP_PASV_ADDRESS` is the address returned
for passive connections and must resolve correctly from the client's network.

Nextcloud mounts `/opt/homeserver/ftp-data`, allowing camera uploads to be made
available through Nextcloud.

## Nextcloud operations

```bash
# List containers and their status.
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Follow the Nextcloud log.
docker exec -it nextcloud-aio-nextcloud tail -f data/nextcloud.log

# Run an occ command.
docker exec --user www-data -it nextcloud-aio-nextcloud \
  php /var/www/html/occ <command>

# Read the AIO interface/Borg password.
docker exec nextcloud-aio-mastercontainer \
  grep password /mnt/docker-aio-config/data/configuration.json
```

The AIO configuration lives in Docker volume `nextcloud_aio_mastercontainer`,
under `data/configuration.json`. Prefer the AIO interface over editing it
directly.

### External SMB storage

Create and verify an external SMB mount:

```bash
docker exec -u www-data -it nextcloud-aio-nextcloud \
  php occ files_external:create /NAS smb password::password \
  -c host="192.168.2.254" \
  -c share="NAS_Public" \
  -c user="admin" \
  -c password="<password>"

docker exec -u www-data -it nextcloud-aio-nextcloud \
  php occ files_external:verify <mount-id>
```

Do not place the real SMB password in this file or shell history. Use a suitable
credential mechanism for the final NAS setup.

Contacts, calendars, and tasks can be synchronized on Android with DAVx5 and a
CalDAV-compatible task application. Configure working email in Nextcloud so
password-reset messages can be delivered.

## PostgreSQL backups

The Stimmapp PostgreSQL container is private. Backups use `docker exec` and
`pg_dump --format=custom`; port `5432` remains unexposed.

The current encrypted first-layer restic repository is:

```text
/opt/homeserver/ftp-data/.stimmapp-postgres-restic
```

This protects against database corruption and accidental deletion, but remains
on the same physical host. Move or replicate it to the NAS or another off-server
destination when available. Detailed backup configuration and recovery steps
are in [`backup/README.md`](backup/README.md).

```bash
systemctl list-timers 'stimmapp-postgres-*'
sudo journalctl \
  -u stimmapp-postgres-backup.service \
  -u stimmapp-postgres-restore-test.service
```

## Mounting a dedicated disk

Use a stable path under `/dev/disk/by-uuid/`. A systemd mount unit must match its
escaped mount path. For `/mnt/storage`, create `mnt-storage.mount`:

```ini
[Unit]
Description=Mount storage disk

[Mount]
What=/dev/disk/by-uuid/<uuid>
Where=/mnt/storage
Type=auto
Options=defaults

[Install]
WantedBy=multi-user.target
```

An optional `mnt-storage.automount` is:

```ini
[Unit]
Description=Automount storage disk

[Automount]
Where=/mnt/storage

[Install]
WantedBy=multi-user.target
```

After creating the mount point and units:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-storage.automount
```

Verify the disk UUID, filesystem, ownership, and mount behavior before moving
live service data.

## Certificate maintenance

The Traefik ACME store contains Let's Encrypt account data and private keys.
Keep `traefik/acme/acme.json` out of Git, mode `0600`, and backed up securely. If
it is exposed, rotate it while someone can monitor the services:

1. Verify the root, `cloud`, and `ftp` DNS records point to this host.
2. Copy `traefik/acme/acme.json` to secure storage outside the repository.
3. Stop Traefik:

   ```bash
   docker compose -f docker-compose.proxy.yml --env-file .env down
   ```

4. Move the compromised store aside and create a protected replacement:

   ```bash
   sudo mv traefik/acme/acme.json \
     "traefik/acme/acme.json.bak.$(date +%Y%m%d-%H%M%S)"
   sudo install -m 600 /dev/null traefik/acme/acme.json
   ```

5. Restart Traefik and visit each HTTPS hostname to trigger issuance:

   ```bash
   docker compose -f docker-compose.proxy.yml --env-file .env up -d
   ```

6. Confirm new certificates were written, then refresh FTPS if required:

   ```bash
   ./scripts/export-traefik-cert.sh ftp.<domain>
   docker compose -f docker-compose.ftp.yml --env-file .env up -d
   ```

7. Verify the website, Nextcloud, and an FTPS client. A default certificate may
   appear briefly while Let's Encrypt issues replacements.

## Maintenance and troubleshooting

Copy a directory while preserving attributes and displaying progress:

```bash
rsync -av --progress /path/to/source/ /path/to/destination/
```

Do not use host-wide `docker stop` or `docker rm` commands for routine work.
Operate on the relevant Compose project so unrelated services remain online.

Outstanding infrastructure work:

- migrate the PostgreSQL restic repository to NAS/off-server storage;
- resolve occasional LAN certificate or DNS-rebind issues with split DNS;
- configure automatic host security and firmware updates carefully;
- review Nextcloud administration warnings after upgrades.

References:

- [Nextcloud All-in-One](https://github.com/nextcloud/all-in-one)
- [Strato DynDNS](https://www.strato.de/faq/hosting/so-einfach-richten-sie-dyndns-fuer-ihre-domains-ein/)
- [Raspberry Pi overlays](https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README)
