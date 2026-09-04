#!/usr/bin/env bash
# cloudflare.sh — attach/detach a public hostname to a local service via the tunnel.
# Locally-managed cloudflared: DNS via `cloudflared tunnel route dns`, ingress in config.yml.

_cf_config(){ echo "${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"; }

_cf_ensure_config() {
  local cfg; cfg="$(_cf_config)"; mkdir -p "$(dirname "$cfg")"
  [ -f "$cfg" ] || cat > "$cfg" <<YML
tunnel: $CLOUDFLARE_TUNNEL_ID
credentials-file: $HOME/.cloudflared/$CLOUDFLARE_TUNNEL_ID.json
ingress:
  - service: http_status:404
YML
}

_cf_reload(){ launchctl kickstart -k system/com.cloudflare.cloudflared 2>/dev/null \
  || sudo cloudflared service restart 2>/dev/null || warn "restart cloudflared to apply"; }

# cf_route_add <hostname> <ip> <port>
cf_route_add() {
  local host="$1" ip="$2" port="$3" cfg; cfg="$(_cf_config)"
  require_env DOMAIN CLOUDFLARE_TUNNEL_ID; _cf_ensure_config
  cloudflared tunnel route dns "$CLOUDFLARE_TUNNEL_ID" "$host" 2>/dev/null || true
  if ! grep -q "hostname: $host" "$cfg"; then
    cp "$cfg" "$cfg.bak.$(date +%s)"
    awk -v h="$host" -v svc="http://$ip:$port" '
      /service: http_status:404/ && !d { print "  - hostname: " h; print "    service: " svc; d=1 } { print }' \
      "$cfg" > "$cfg.new" && mv "$cfg.new" "$cfg"
  fi
  _cf_reload; ok "routed $host → http://$ip:$port"
}

# cf_route_remove <hostname>
cf_route_remove() {
  local host="$1" cfg; cfg="$(_cf_config)"; [ -f "$cfg" ] || return 0
  cp "$cfg" "$cfg.bak.$(date +%s)"
  awk -v h="$host" '$0 ~ ("hostname: " h){s=2;next} s>0{s--;next} {print}' "$cfg" > "$cfg.new" && mv "$cfg.new" "$cfg"
  _cf_reload; ok "removed route for $host"
}
