#!/usr/bin/env bash
# Append the couchmc.linloir.cn entry to the existing Caddyfile (if missing)
# and trigger a graceful reload of the Caddy container so existing sites
# stay up.
set -euo pipefail

CADDYFILE="/home/ubuntu/docker_caddy/data/caddyfile/Caddyfile"
DOMAIN="couchmc.linloir.cn"
UPSTREAM="127.0.0.1:23010"

if [ ! -f "$CADDYFILE" ]; then
  echo "Caddyfile not found at $CADDYFILE" >&2
  exit 1
fi

cp "$CADDYFILE" "$CADDYFILE.bak.$(date +%Y%m%d_%H%M%S)"

if grep -q "$DOMAIN" "$CADDYFILE"; then
  echo "Entry for $DOMAIN already present, leaving Caddyfile untouched."
else
  cat >> "$CADDYFILE" <<EOF

$DOMAIN {
  reverse_proxy $UPSTREAM
  tls {
    dns cloudflare {env.CF_API_TOKEN}
    resolvers 1.1.1.1
  }
}
EOF
  echo "Appended $DOMAIN entry to Caddyfile."
fi

echo "--- Validating Caddyfile inside the container ---"
sudo docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

echo "--- Reloading Caddy (graceful, no downtime for other sites) ---"
sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

echo "--- Final Caddyfile ---"
cat "$CADDYFILE"
