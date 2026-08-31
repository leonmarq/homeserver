#!/usr/bin/env bash
set -Eeuo pipefail

config_file="${STIMMAPP_BACKUP_CONFIG:-/etc/stimmapp-postgres-backup.env}"
if [[ ! -r "${config_file}" ]]; then
  echo "backup config is not readable: ${config_file}" >&2
  exit 1
fi

# Export backend credentials and restic settings to child processes.
set -a
# shellcheck disable=SC1090
source "${config_file}"
set +a

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"

restic_command="${RESTIC_COMMAND:-restic}"
container="${POSTGRES_CONTAINER:-stimmapp-dev-postgres}"
database="${POSTGRES_DATABASE:-stimmapp_pid_verifier}"
db_user="${POSTGRES_USER:-stimmapp_pid_verifier}"
staging_dir="${BACKUP_STAGING_DIR:-/var/lib/stimmapp-postgres-backup}"
dump_file="${staging_dir}/${database}.dump"
lock_file="${staging_dir}/backup.lock"

install -d -m 700 "${staging_dir}"
exec 9>"${lock_file}"
if ! flock -n 9; then
  echo "another PostgreSQL backup is already running" >&2
  exit 1
fi

cleanup() {
  rm -f -- "${dump_file}"
}
trap cleanup EXIT

umask 077
docker inspect "${container}" >/dev/null
docker exec "${container}" pg_isready -U "${db_user}" -d "${database}" >/dev/null
docker exec "${container}" pg_dump \
  --username="${db_user}" \
  --dbname="${database}" \
  --format=custom \
  --compress=9 \
  --no-owner \
  --no-privileges >"${dump_file}"

[[ -s "${dump_file}" ]] || {
  echo "pg_dump produced an empty file" >&2
  exit 1
}

# Reading the table of contents catches a truncated or invalid custom dump.
docker exec -i "${container}" pg_restore --list <"${dump_file}" >/dev/null

"${restic_command}" backup \
  --tag stimmapp-postgres \
  --host "$(hostname -s)" \
  "${dump_file}"

"${restic_command}" forget \
  --tag stimmapp-postgres \
  --keep-daily "${RESTIC_KEEP_DAILY:-30}" \
  --prune

echo "PostgreSQL backup completed and retention applied"
