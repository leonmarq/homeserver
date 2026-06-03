# Multi-service setup (Traefik + Nextcloud AIO + FTP/FTPS)

This folder now uses **multiple compose files**:

- `docker-compose.proxy.yml`: Traefik reverse proxy + `<domain_name>.com` hello page
- `docker-compose.yml`: Nextcloud AIO master container (proxied through Traefik)
- `docker-compose.ftp.yml`: FTP/FTPS server on `ftp.<domain_name>.com`

## Why multiple compose files?

Yes, this is recommended. It keeps blast radius low and makes updates easier:

- proxy can restart independently
- Nextcloud AIO remains close to official config
- FTP can be changed/replaced without touching cloud/proxy

## Important protocol note

`cloud.<domain_name>.com` and `<domain_name>.com` are reverse-proxied by Traefik (HTTP/HTTPS).

FTP is **not HTTP**, so it is exposed directly on ports `21` and `21000-21003`.
You still use DNS name `ftp.<domain_name>.com`.

## DNS (DynDNS)

Create/keep these records pointing to your home public IP (via DynDNS updates):

- `<domain_name>.com` -> your public IP
- `cloud.<domain_name>.com` -> your public IP
- `ftp.<domain_name>.com` -> your public IP

## Router/NAT forwards to this Docker host

- TCP `80` -> host `80`
- TCP `443` -> host `443`
- TCP `21` -> host `21`
- TCP `21000-21003` -> host `21000-21003`

## Bring up services

From `/opt/com_<domain_name>`:

```bash
docker compose -f docker-compose.proxy.yml --env-file .env up -d
docker compose -f docker-compose.nextcloud.yml --env-file .env up -d
docker compose -f docker-compose.ftp.yml --env-file .env up -d
```

For FTPS, create a certificate before starting the FTP stack:

```bash
./scripts/generate-ftps-cert.sh
```

Then open:

- Nextcloud AIO UI: `https://<server-ip>:8080`
- Root page: `https://<domain_name>.com`
- Cloud: `https://cloud.<domain_name>.com`
- FTP host in client: `ftp.<domain_name>.com` (Explicit FTPS on port `21`)

## FTP variables

- `FTP_DOMAIN`: the hostname clients use, for example `ftp.<domain_name>.com`
- `FTP_PASV_ADDRESS`: the address returned for passive connections

For your Nextcloud container on the same host, `FTP_PASV_ADDRESS` should stay on the LAN IP. If you also need external clients, use split DNS so `ftp.<domain_name>.com` resolves to the LAN IP internally and the public IP externally.

## Nextcloud AIO first-run

In AIO, use domain `cloud.<domain_name>.com` and finish setup normally.

## Reserve space for third service

Add a new compose file like `docker-compose.service3.yml`, connect service to `proxy` network, then attach Traefik labels (or a dynamic file route).

## Homecloud:
### inital Setup:
- make sure my server has a stable connection with a static local Ip-Adress
- find a Domain. I use Strato currently.
- create a subdomain with prefix: cloud.<domainname>. then find your homenetworks public-ip and set the A record.
- follow the provided guide with no extra features: https://github.com/nextcloud/all-in-one
- make sure it's acessible from outside your LAN.
- If the public Ip changes regularly, get flexible and set a DynDNS instead of A record:
  - tutorial for my setup: https://www.strato.de/faq/hosting/so-einfach-richten-sie-dyndns-fuer-ihre-domains-ein/
  - otherwise what to do is set domain to dynDns instead of A record. then you need to configure your router to connect your server with the service.
  - For my setup local access was blocked, because of ipv6 dyndns support interfering with DNS-Rebind protection and quick fix is to not implement <ip6addr>

### further improvements
- set automatic updates as found in the nextcloud-aio Docs
- Backup: set up a proper SSD with ext4-fileformat and automounting via /etc/fstab. Then configure borg-backup.
- Email-Server: configured it with my mail account wich was provided with the domain by strato. Good for resetting your password!
- Phone-Sync: Contacts, Calendar, Task-list work alright with Davx5 and Tasks, which i got for free from F-Droid.

- Bonus: get rid of all warnings in your nc-settings.

### be careful with:
- optional NC containers which like to use ports, like to interfere and lead to random bugs.
- saving all your passwords well. I'm still with keepass on usb since 12 year old for all the rudimentary.

### still working on
- resolve occasional certificate-issues when trying to access from the local net. Solvable with PiHole or BIND?
- FTP-compatability: nextcloud-aio does not support connecting via ftp. but my security camera can only transfer to ftp. i need a secondary ftp-instance. which i can access from both nextcloud and the camera...

### Useful commands:
#### AIO interface/borg password
`sudo docker exec nextcloud-aio-mastercontainer grep password /mnt/docker-aio-config/data/configuration.json`

## additional improvements
- add cronjobs for automatic firmware-updates.

## Sources:
- https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README
- https://github.com/lmarquar/Nextcloud_on_Raspi_commands
-
