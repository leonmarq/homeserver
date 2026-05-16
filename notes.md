check log:
sudo docker exec -it nextcloud-aio-nextcloud tail data/nextcloud.log

check config:
/var/lib/docker/volumes/nextcloud_aio_mastercontainer/_data/data/configuration.json

or make changes:
sudo docker run -it --rm --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config:rw alpine sh -c "apk add --no-cache nano && nano /mnt/docker-aio-config/data/configuration.json"

or execute other commands:
sudo docker exec --user www-data -it nextcloud-aio-nextcloud php /var/www/html/occ your-command-here

remove all containers:
docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q)

copy files:
rsync -av --progress /path/to/source-folder/ /path/to/destination-folder/

list containers:
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

Traefik / Let's Encrypt rotation task after holiday:

Reason:
- `traefik/acme/acme.json` contained exposed Let's Encrypt account and certificate private key material.
- Keys should be treated as compromised and rotated when someone can watch the services.

Safe rotation plan:
1. Verify DNS for `aiomvp.com`, `cloud.aiomvp.com`, and `ftp.aiomvp.com` still points to the home public IP.
2. Create a backup of `/opt/homeserver/traefik/acme/acme.json` outside the repo.
3. Stop the proxy stack:
   `docker compose -f docker-compose.proxy.yml --env-file .env down`
4. Remove the old ACME store and create a fresh empty one with strict permissions:
   `mv /opt/homeserver/traefik/acme/acme.json /opt/homeserver/traefik/acme/acme.json.bak.$(date +%Y%m%d-%H%M%S)`
   `install -m 600 /dev/null /opt/homeserver/traefik/acme/acme.json`
5. Start the proxy stack again:
   `docker compose -f docker-compose.proxy.yml --env-file .env up -d`
6. Trigger certificate issuance by opening:
   `https://aiomvp.com`
   `https://cloud.aiomvp.com`
   `https://ftp.aiomvp.com`
7. Confirm new certificates were written into the new `acme.json`.
8. Re-export FTPS certs if needed:
   `./scripts/export-traefik-cert.sh ftp.aiomvp.com`
9. Restart the FTP stack if the FTPS service needs the refreshed files:
   `docker compose -f docker-compose.ftp.yml --env-file .env up -d`
10. Verify:
   - Traefik container is healthy and serving HTTPS
   - Nextcloud loads normally
   - FTP/FTPS clients can still connect

Notes:
- This rotates the live leaf certificates and also causes Traefik to register a fresh ACME account.
- There may be a short window where HTTPS serves default/self-signed certs until Let's Encrypt finishes issuance.
- Because the current private keys were exposed in a public repo, rotation is recommended even if the services still work today.
