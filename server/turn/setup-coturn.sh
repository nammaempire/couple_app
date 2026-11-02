#!/usr/bin/env bash
# Sets up the TURN relay for Us calls on a fresh Ubuntu 22.04/24.04 server.
#
# Usage (as root, on the VPS):
#   bash setup-coturn.sh                  # plain TURN on port 3478 (UDP + TCP)
#   bash setup-coturn.sh turn.example.com # also TURN over TLS on 443, for
#                                         # networks that only allow HTTPS
#
# For the TLS option, first point the domain's DNS (an A record) at this
# server's IP address. At the end the script prints the three variables to
# add to the us-server service on Railway.
set -euo pipefail

DOMAIN="${1:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0 ${DOMAIN}" >&2
  exit 1
fi

echo "==> Installing coturn"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y coturn curl openssl ufw

PUBLIC_IP="$(curl -4 -fsS https://api.ipify.org || true)"
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="$(hostname -I | awk '{print $1}')"
fi
PRIVATE_IP="$(hostname -I | awk '{print $1}')"

# Keep the secret if the script is run again, so the server's value stays valid.
SECRET_FILE=/etc/coturn-us-secret
if [[ ! -s "$SECRET_FILE" ]]; then
  openssl rand -hex 32 > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi
SECRET="$(cat "$SECRET_FILE")"

TLS_LINES=""
if [[ -n "$DOMAIN" ]]; then
  echo "==> Getting a certificate for $DOMAIN"
  apt-get install -y certbot
  ufw allow 80/tcp >/dev/null || true
  certbot certonly --standalone --non-interactive --agree-tos \
    --register-unsafely-without-email -d "$DOMAIN"
  mkdir -p /etc/coturn/certs
  install -m 640 -g turnserver "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/coturn/certs/fullchain.pem
  install -m 640 -g turnserver "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/coturn/certs/privkey.pem
  # Renewals copy the new certificate in and restart coturn.
  cat > /etc/letsencrypt/renewal-hooks/deploy/coturn.sh <<HOOK
#!/bin/sh
install -m 640 -g turnserver /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/coturn/certs/fullchain.pem
install -m 640 -g turnserver /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/coturn/certs/privkey.pem
systemctl restart coturn
HOOK
  chmod +x /etc/letsencrypt/renewal-hooks/deploy/coturn.sh
  TLS_LINES="tls-listening-port=443
cert=/etc/coturn/certs/fullchain.pem
pkey=/etc/coturn/certs/privkey.pem
no-tlsv1
no-tlsv1_1"
fi

echo "==> Writing /etc/turnserver.conf"
REALM="${DOMAIN:-us-turn}"
cat > /etc/turnserver.conf <<CONF
# TURN relay for Us calls (written by setup-coturn.sh).
listening-port=3478
${TLS_LINES}
listening-ip=${PRIVATE_IP}
relay-ip=${PRIVATE_IP}
external-ip=${PUBLIC_IP}/${PRIVATE_IP}
min-port=49152
max-port=65535

# Short-lived logins made by the Us server (TURN_SECRET); nothing is stored
# in the app.
use-auth-secret
static-auth-secret=${SECRET}
realm=${REALM}
fingerprint

# Only relay to the public internet, never into this server's own network.
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=198.18.0.0-198.19.255.255
denied-peer-ip=::1
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff

# A call uses one or two relays; this stops one login being abused.
user-quota=12
total-quota=1200
stale-nonce=600
no-cli
no-software-attribute
log-file=syslog
simple-log
CONF

# coturn on Ubuntu needs this to start as a service.
if [[ -f /etc/default/coturn ]]; then
  sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
fi
# Port 443 is below 1024.
if [[ -n "$DOMAIN" ]]; then
  mkdir -p /etc/systemd/system/coturn.service.d
  cat > /etc/systemd/system/coturn.service.d/override.conf <<UNIT
[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
UNIT
  systemctl daemon-reload
fi

echo "==> Opening the firewall"
ufw allow OpenSSH >/dev/null
ufw allow 3478/udp >/dev/null
ufw allow 3478/tcp >/dev/null
ufw allow 49152:65535/udp >/dev/null
[[ -n "$DOMAIN" ]] && ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

systemctl enable coturn >/dev/null
systemctl restart coturn
sleep 2
systemctl is-active --quiet coturn || { echo "coturn did not start; see: journalctl -u coturn" >&2; exit 1; }

HOST="${DOMAIN:-$PUBLIC_IP}"
URLS="turn:${HOST}:3478?transport=udp,turn:${HOST}:3478?transport=tcp"
[[ -n "$DOMAIN" ]] && URLS="${URLS},turns:${DOMAIN}:443?transport=tcp"

cat <<DONE

==========================================================================
 TURN relay is running. Add these variables to the us-server service on
 Railway (Variables tab), then click Deploy:

   TURN_URLS=${URLS}
   TURN_SECRET=${SECRET}
   TURN_TTL_SECONDS=21600

 Keep TURN_SECRET private. It's also saved in ${SECRET_FILE} on this server.
==========================================================================
DONE
