#!/usr/bin/env bash
# cloudflare-route.sh — attach/detach a public hostname to a local service via the tunnel.
#
#   cloudflare-route.sh add    <hostname> <ip> <port>
#   cloudflare-route.sh remove <hostname>
#
# Uses a locally-managed cloudflared tunnel: DNS via `cloudflared tunnel route dns`,
# ingress rules in ~/.cloudflared/config.yml. Requires DOMAIN + CLOUDFLARE_TUNNEL_ID in .env.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/lib.sh"
load_env
need_tool cloudflared
require_env DOMAIN CLOUDFLARE_TUNNEL_ID

CFG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
action="${1:-}"; host="${2:-}"; ip="${3:-}"; port="${4:-}"
[ -n "$host" ] || die "usage: cloudflare-route.sh add|remove <hostname> [ip] [port]"

ensure_cfg() {
  mkdir -p "$(dirname "$CFG")"
  [ -f "$CFG" ] || cat > "$CFG" <<YML
tunnel: $CLOUDFLARE_TUNNEL_ID
credentials-file: $HOME/.cloudflared/$CLOUDFLARE_TUNNEL_ID.json
ingress:
  - service: http_status:404
YML
}

reload_tunnel() { launchctl kickstart -k "system/com.cloudflare.cloudflared" 2>/dev/null \
  || sudo cloudflared service restart 2>/dev/null || warn "restart cloudflared manually to apply"; }

case "$action" in
  add)
    [ -n "$ip" ] && [ -n "$port" ] || die "add needs <ip> <port>"
    ensure_cfg
    # DNS: hostname -> tunnel
    cloudflared tunnel route dns "$CLOUDFLARE_TUNNEL_ID" "$host" 2>/dev/null || true
    # ingress: insert before the catch-all 404 (idempotent)
    if ! grep -q "hostname: $host" "$CFG"; then
      cp "$CFG" "$CFG.bak.$(date +%s)"
      awk -v h="$host" -v svc="http://$ip:$port" '
        /service: http_status:404/ && !done { print "  - hostname: " h; print "    service: " svc; done=1 }
        { print }' "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"
    fi
    reload_tunnel; ok "routed $host -> http://$ip:$port"
    ;;
  remove)
    [ -f "$CFG" ] || exit 0
    cp "$CFG" "$CFG.bak.$(date +%s)"
    # drop the 2-line ingress block for this hostname
    awk -v h="$host" '
      $0 ~ ("hostname: " h) { skip=2; next }
      skip>0 { skip--; next }
      { print }' "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"
    reload_tunnel; ok "removed route for $host (DNS record left in place; delete in CF dashboard if desired)"
    ;;
  *) die "unknown action: $action";;
esac
