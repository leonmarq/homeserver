#!/bin/sh

set -eu

if test "${DONT_GEN_SSL_CERT-set}" = set; then
mkdir -p /tmp/ssl/
cd /tmp/ssl/
mkdir -p certs/ca
openssl genrsa -out certs/ca/root.key.pem 2048
openssl req -x509 -new -nodes -key certs/ca/root.key.pem -days 9131 -out certs/ca/root.crt.pem -subj "/C=DE/ST=BW/L=Stuttgart/O=Dummy Authority/CN=Dummy Authority"
mkdir -p certs/servers
mkdir -p certs/tmp
mkdir -p certs/servers/localhost
openssl genrsa -out certs/servers/localhost/privkey.pem 2048
if test "${cert_domain-set}" = set; then
openssl req -key certs/servers/localhost/privkey.pem -new -sha256 -out certs/tmp/localhost.csr.pem -subj "/C=DE/ST=BW/L=Stuttgart/O=Dummy Authority/CN=localhost"
else
openssl req -key certs/servers/localhost/privkey.pem -new -sha256 -out certs/tmp/localhost.csr.pem -subj "/C=DE/ST=BW/L=Stuttgart/O=Dummy Authority/CN=${cert_domain}"
fi
openssl x509 -req -in certs/tmp/localhost.csr.pem -CA certs/ca/root.crt.pem -CAkey certs/ca/root.key.pem -CAcreateserial -out certs/servers/localhost/cert.pem -days 9131
cert_params="\
 --o:ssl.cert_file_path=/tmp/ssl/certs/servers/localhost/cert.pem \
 --o:ssl.key_file_path=/tmp/ssl/certs/servers/localhost/privkey.pem \
 --o:ssl.ca_file_path=/tmp/ssl/certs/ca/root.crt.pem"
fi

user_id=$(id -u)
group_id=$(id -g)
if [ "$user_id" -ne 1001 ]; then
  passwd_entry="cool:x:${user_id}:${group_id}::/opt/cool:/usr/sbin/nologin"

  if ls /lib/ld-musl-* >/dev/null 2>&1; then
    echo "$passwd_entry" >> /etc/passwd
  else
    echo "$passwd_entry" >/tmp/passwd
    export NSS_WRAPPER_PASSWD=/tmp/passwd
    export NSS_WRAPPER_GROUP=/etc/group
    export LD_PRELOAD=libnss_wrapper.so
  fi
fi

cat >/tmp/coolwsd-alias-groups.xml <<'EOF'
            <alias_groups desc="default mode is 'first' it allows only the first host connecting to coolwsd when groups are not defined. set mode to 'groups' and define group to allow multiple host and its aliases" mode="groups">
                <group>
                    <host desc="hostname to allow or deny." allow="true">http://nextcloud-aio-apache:23973</host>
                    <alias desc="regex pattern of aliasname">https://cloud.aiomvp.com:443</alias>
                </group>
            </alias_groups>
EOF

awk '
  /<alias_groups desc=.*mode="first">/ {
    while ((getline line < "/tmp/coolwsd-alias-groups.xml") > 0) {
      print line
    }
    skip = 1
    next
  }
  skip && /<\/alias_groups>/ {
    skip = 0
    next
  }
  !skip { print }
' /etc/coolwsd/coolwsd.xml > /tmp/coolwsd.xml
mv /tmp/coolwsd.xml /etc/coolwsd/coolwsd.xml

exec /usr/bin/coolwsd --version --use-env-vars ${cert_params:-} --o:sys_template_path=/opt/cool/systemplate --o:child_root_path=/opt/cool/child-roots --o:file_server_root_path=/usr/share/coolwsd --o:cache_files.path=/opt/cool/cache --o:logging.color=false --o:stop_on_config_change=true ${extra_params:-} "$@"
