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
source_database="${POSTGRES_DATABASE:-stimmapp_pid_verifier}"
db_user="${POSTGRES_USER:-stimmapp_pid_verifier}"
staging_dir="${BACKUP_STAGING_DIR:-/var/lib/stimmapp-postgres-backup}"
dump_path="${staging_dir}/${source_database}.dump"
test_database="restore_test_$(date -u +%Y%m%d_%H%M%S)_$$"

cleanup() {
  docker exec "${container}" psql --username="${db_user}" --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${test_database}' AND pid <> pg_backend_pid();" \
    --command="DROP DATABASE IF EXISTS \"${test_database}\";" >/dev/null || true
}
trap cleanup EXIT

docker exec "${container}" pg_isready -U "${db_user}" -d postgres >/dev/null
"${restic_command}" snapshots --tag stimmapp-postgres --latest 1 >/dev/null

docker exec "${container}" createdb --username="${db_user}" "${test_database}"
"${restic_command}" dump --tag stimmapp-postgres latest "${dump_path}" | \
  docker exec -i "${container}" pg_restore \
    --username="${db_user}" \
    --dbname="${test_database}" \
    --no-owner \
    --no-privileges \
    --exit-on-error

table_count="$(docker exec "${container}" psql \
  --username="${db_user}" \
  --dbname="${test_database}" \
  --tuples-only --no-align \
  --command="SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');")"

echo "Restore test succeeded in ${test_database}; restored ${table_count} user tables"
