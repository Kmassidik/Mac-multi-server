#!/usr/bin/env bash
# cloudflare.sh — attach/detach a public hostname to a local service.
#
# Works with a REMOTELY-MANAGED (token) tunnel — the kind cloudflared runs via --token.
# Routes are managed through the Cloudflare API (not a local config.yml):
#   1. add an ingress rule to the tunnel config   (hostname → http://ip:port)
#   2. add a DNS CNAME  hostname → <tunnel>.cfargotunnel.com  (proxied)
# Needs: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_ZONE_ID, CLOUDFLARE_TUNNEL_ID.

CF_API="https://api.cloudflare.com/client/v4"

_cf() { # METHOD PATH [JSON]
  local m="$1" p="$2" d="${3:-}"
  curl -s -X "$m" "$CF_API$p" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" ${d:+--data "$d"}
}
_cf_ok() { python3 -c 'import sys,json;print("ok" if json.load(sys.stdin).get("success") else "err")' 2>/dev/null; }

# cf_route_add <hostname> <ip> <port>
cf_route_add() {
  local host="$1" ip="$2" port="$3"
  require_env CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID CLOUDFLARE_TUNNEL_ID
  local base="/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$CLOUDFLARE_TUNNEL_ID/configurations"

  # 1. ingress rule (merge into existing config, keep catch-all last)
  local newcfg
  newcfg=$(_cf GET "$base" | python3 -c '
import sys,json
host,ip,port=sys.argv[1:4]
cfg=(json.load(sys.stdin).get("result") or {}).get("config") or {}
ing=[r for r in cfg.get("ingress",[]) if r.get("hostname")!=host and "hostname" in r]
ing.append({"hostname":host,"service":f"http://{ip}:{port}"})
ing.append({"service":"http_status:404"})
cfg["ingress"]=ing
print(json.dumps({"config":cfg}))' "$host" "$ip" "$port") || { warn "cf: build config failed"; return 1; }
  local r; r=$(_cf PUT "$base" "$newcfg" | _cf_ok)
  [ "$r" = ok ] || { warn "cf: ingress update failed for $host"; return 1; }

  # 2. DNS CNAME → tunnel (create or update)
  local body id
  body="{\"type\":\"CNAME\",\"name\":\"$host\",\"content\":\"$CLOUDFLARE_TUNNEL_ID.cfargotunnel.com\",\"proxied\":true}"
  id=$(_cf GET "/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$host" \
        | python3 -c 'import sys,json;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
  if [ -n "$id" ]; then _cf PUT "/zones/$CLOUDFLARE_ZONE_ID/dns_records/$id" "$body" >/dev/null
  else _cf POST "/zones/$CLOUDFLARE_ZONE_ID/dns_records" "$body" >/dev/null; fi
  ok "routed $host → http://$ip:$port"
}

# cf_route_remove <hostname>
cf_route_remove() {
  local host="$1"
  require_env CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID CLOUDFLARE_TUNNEL_ID
  local base="/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$CLOUDFLARE_TUNNEL_ID/configurations"

  local newcfg
  newcfg=$(_cf GET "$base" | python3 -c '
import sys,json
host=sys.argv[1]
cfg=(json.load(sys.stdin).get("result") or {}).get("config") or {}
ing=[r for r in cfg.get("ingress",[]) if r.get("hostname")!=host and "hostname" in r]
ing.append({"service":"http_status:404"})
cfg["ingress"]=ing
print(json.dumps({"config":cfg}))' "$host")
  _cf PUT "$base" "$newcfg" >/dev/null

  local id
  id=$(_cf GET "/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$host" \
        | python3 -c 'import sys,json;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
  [ -n "$id" ] && _cf DELETE "/zones/$CLOUDFLARE_ZONE_ID/dns_records/$id" >/dev/null
  ok "removed route for $host"
}
