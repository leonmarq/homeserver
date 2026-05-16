#!/usr/bin/env bash
set -euo pipefail

cp /etc/vsftpd/vsftpd.conf.template /etc/vsftpd/vsftpd.conf
chown root:root /etc/vsftpd/vsftpd.conf
chmod 600 /etc/vsftpd/vsftpd.conf

exec /usr/sbin/run-vsftpd.sh "$@"
