#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${repo_root}/.env"

if [[ ! -f "${env_file}" ]]; then
  echo "missing ${env_file}" >&2
  exit 1
fi

ftp_domain="$(awk -F= '/^FTP_DOMAIN=/{print $2}' "${env_file}")"
if [[ -z "${ftp_domain}" ]]; then
  echo "FTP_DOMAIN is not set in ${env_file}" >&2
  exit 1
fi

cert_dir="${repo_root}/ftp-certs"
mkdir -p "${cert_dir}"

openssl req -x509 -nodes -newkey rsa:4096 -sha256 -days 825 \
  -keyout "${cert_dir}/ftp.key" \
  -out "${cert_dir}/ftp.crt" \
  -subj "/CN=${ftp_domain}" \
  -addext "subjectAltName=DNS:${ftp_domain}"

chmod 600 "${cert_dir}/ftp.key"
chmod 644 "${cert_dir}/ftp.crt"

echo "created ${cert_dir}/ftp.crt and ${cert_dir}/ftp.key for ${ftp_domain}"
