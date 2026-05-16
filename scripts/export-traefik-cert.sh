#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <domain> [output-dir]" >&2
  exit 1
fi

domain="$1"
output_dir="${2:-/opt/homeserver/ftp-certs}"
acme_file="/opt/homeserver/traefik/acme/acme.json"

if [[ ! -f "${acme_file}" ]]; then
  echo "missing ${acme_file}" >&2
  exit 1
fi

cert_b64="$(jq -r --arg domain "${domain}" '
  .letsencrypt.Certificates[]
  | select(.domain.main == $domain)
  | .certificate
' "${acme_file}" | tail -n 1)"

key_b64="$(jq -r --arg domain "${domain}" '
  .letsencrypt.Certificates[]
  | select(.domain.main == $domain)
  | .key
' "${acme_file}" | tail -n 1)"

if [[ -z "${cert_b64}" || -z "${key_b64}" || "${cert_b64}" == "null" || "${key_b64}" == "null" ]]; then
  echo "certificate for ${domain} not found in ${acme_file}" >&2
  exit 1
fi

install -d -m 755 "${output_dir}"
printf '%s' "${cert_b64}" | base64 -d > "${output_dir}/ftp.crt"
printf '%s' "${key_b64}" | base64 -d > "${output_dir}/ftp.key"
chmod 644 "${output_dir}/ftp.crt"
chmod 600 "${output_dir}/ftp.key"

echo "wrote ${output_dir}/ftp.crt and ${output_dir}/ftp.key for ${domain}"
