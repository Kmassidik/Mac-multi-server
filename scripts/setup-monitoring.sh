#!/usr/bin/env bash
# setup-monitoring.sh — install Netdata on the host and expose it via Cloudflare.
# Netdata gives live CPU/RAM/net dashboards out of the box on :19999.
# (Per-VPS agents stream to this host parent — added at deploy time; see docs.)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/lib.sh"
load_env

log "installing Netdata…"
brew list netdata >/dev/null 2>&1 || brew install netdata
# bind to localhost only — exposed solely through Cloudflare
NETDATA_CONF="$(brew --prefix)/etc/netdata/netdata.conf"
if [ -f "$NETDATA_CONF" ] && ! grep -q 'bind to = 127.0.0.1' "$NETDATA_CONF"; then
  warn "set '[web] bind to = 127.0.0.1' in $NETDATA_CONF to keep it host-local"
fi
brew services start netdata >/dev/null 2>&1 || true
ok "Netdata on http://127.0.0.1:19999"

# expose via Cloudflare (monitor subdomain)
if cloudflare_ready; then
  SUB="${GRAFANA_SUBDOMAIN:-monitor}"
  "$HERE/cloudflare-route.sh" add "${SUB}.${DOMAIN}" 127.0.0.1 19999 \
    && ok "monitoring: https://${SUB}.${DOMAIN}" || warn "cloudflare route for monitoring failed"
else
  warn "Cloudflare not configured — monitoring reachable locally at :19999 only"
fi
