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

# _cf_ingress_put <hostname> <service>  — merge one ingress rule, keep the 404 catch-all last
_cf_ingress_put() {
  local host="$1" svc="$2"
  local base="/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$CLOUDFLARE_TUNNEL_ID/configurations"
  local newcfg
  newcfg=$(_cf GET "$base" | python3 -c '
import sys,json
host,svc=sys.argv[1:3]
cfg=(json.load(sys.stdin).get("result") or {}).get("config") or {}
ing=[r for r in cfg.get("ingress",[]) if r.get("hostname")!=host and "hostname" in r]
ing.append({"hostname":host,"service":svc})
ing.append({"service":"http_status:404"})
cfg["ingress"]=ing
print(json.dumps({"config":cfg}))' "$host" "$svc") || return 1
  [ "$(_cf PUT "$base" "$newcfg" | _cf_ok)" = ok ]
}

# _cf_dns_cname <hostname>  — point hostname at the tunnel (create or update, proxied)
_cf_dns_cname() {
  local host="$1" body id
  body="{\"type\":\"CNAME\",\"name\":\"$host\",\"content\":\"$CLOUDFLARE_TUNNEL_ID.cfargotunnel.com\",\"proxied\":true}"
  id=$(_cf GET "/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$host" \
        | python3 -c 'import sys,json;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
  if [ -n "$id" ]; then _cf PUT "/zones/$CLOUDFLARE_ZONE_ID/dns_records/$id" "$body" >/dev/null
  else _cf POST "/zones/$CLOUDFLARE_ZONE_ID/dns_records" "$body" >/dev/null; fi
}

# cf_route_add <hostname> <ip> <port>  — HTTP service (panel, monitor, web apps)
cf_route_add() {
  local host="$1" ip="$2" port="$3"
  require_env CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID CLOUDFLARE_TUNNEL_ID
  _cf_ingress_put "$host" "http://$ip:$port" || { warn "cf: ingress update failed for $host"; return 1; }
  _cf_dns_cname "$host"
  ok "routed $host → http://$ip:$port"
}

# cf_ssh_route_add <hostname> <ip>  — SSH service, reached with `cloudflared access ssh`.
# Hides both public and internal IPs: tenants ssh to the hostname, never an address.
cf_ssh_route_add() {
  local host="$1" ip="$2"
  require_env CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID CLOUDFLARE_TUNNEL_ID
  _cf_ingress_put "$host" "ssh://$ip:22" || { warn "cf: ssh ingress update failed for $host"; return 1; }
  _cf_dns_cname "$host"
  ok "routed $host → ssh://$ip:22"
}

# cf_sweep_platform — remove EVERY platform host from the domain (tunnel ingress + DNS):
# panel.$DOMAIN, monitor.$DOMAIN, and any vps<N>.$DOMAIN. Leaves ssh.$DOMAIN and all other
# records untouched. Catches orphans whose local state is already gone. Really clean.
cf_sweep_platform() {
  require_env CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID CLOUDFLARE_TUNNEL_ID
  local panel="${PANEL_SUBDOMAIN:-panel}" mon="${GRAFANA_SUBDOMAIN:-monitor}"
  local base="/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$CLOUDFLARE_TUNNEL_ID/configurations"

  # hostnames from tunnel ingress that match our patterns
  local from_ingress from_dns hosts
  from_ingress=$(_cf GET "$base" | python3 -c '
import sys,json,re
dom,panel,mon=sys.argv[1:4]
cfg=(json.load(sys.stdin).get("result") or {}).get("config") or {}
pat=re.compile(r"^(?:%s|%s|vps[0-9]+)\.%s$"%(re.escape(panel),re.escape(mon),re.escape(dom)))
for r in cfg.get("ingress",[]):
    h=r.get("hostname","")
    if h and pat.match(h): print(h)' "$DOMAIN" "$panel" "$mon" 2>/dev/null)

  # names from DNS records that match (in case ingress is gone but DNS lingers)
  from_dns=$(_cf GET "/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=200" | python3 -c '
import sys,json,re
dom,panel,mon=sys.argv[1:4]
recs=json.load(sys.stdin).get("result") or []
pat=re.compile(r"^(?:%s|%s|vps[0-9]+)\.%s$"%(re.escape(panel),re.escape(mon),re.escape(dom)))
for r in recs:
    n=r.get("name","")
    if pat.match(n): print(n)' "$DOMAIN" "$panel" "$mon" 2>/dev/null)

  hosts=$(printf '%s\n%s\n' "$from_ingress" "$from_dns" | sort -u | grep -v '^$')
  if [ -z "$hosts" ]; then ok "domain already clean (no platform records)"; return 0; fi
  while read -r h; do [ -n "$h" ] && cf_route_remove "$h"; done <<< "$hosts"
  ok "domain swept clean (ssh.$DOMAIN and other records preserved)"
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
