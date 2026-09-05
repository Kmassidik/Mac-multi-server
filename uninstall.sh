#!/usr/bin/env bash
# uninstall.sh — remove everything the platform created. Clean, like docker/nix.
#
#   ./uninstall.sh          remove all VPS, the panel, monitoring routes, state + services
#   ./uninstall.sh --purge  also remove cached base images + the DNS helper daemon
#
# Leaves alone: the brew tools (tart, cloudflared, netdata, sshpass) — cloudflared runs your
# SSH tunnel, so removing it could cut access. It prints how to remove them yourself if you want.
# Also leaves the repo folder itself (you're running from it) — rm -rf it afterward to finish.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cloudflare.sh"; . "$HERE/lib/vps.sh"

PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1
load_env 2>/dev/null || warn ".env not loaded — Cloudflare routes won't be removed"

echo "This removes all VPS and the Mac-multi-server services from this Mac."
printf "Continue? [y/N] "; read -r a; [ "$a" = y ] || [ "$a" = Y ] || { echo "aborted."; exit 0; }

# 1. destroy every VPS (VM + launchd + cloudflare route + state, via the same engine)
log "removing VPS…"
if [ -d "$STATE_DIR" ]; then
  for f in "$STATE_DIR"/vps-*.json; do [ -e "$f" ] || continue; vps_destroy "$(basename "$f" .json)" || true; done
fi

# 1b. health watchdog (gui-domain LaunchAgent) + per-VPS health sidecars
log "removing health watchdog…"
WD=io.macmultiserver.watchdog
launchctl bootout "gui/$(id -u)/$WD" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$WD.plist"
[ -d "$STATE_DIR" ] && rm -f "$STATE_DIR"/*.health 2>/dev/null || true

# 2. control-plane panel (LaunchDaemon now; also clean the old LaunchAgent form)
log "removing control plane…"
PL=io.macmultiserver.panel
launchctl bootout "gui/$(id -u)/$PL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$PL.plist"
sudo launchctl bootout "system/$PL" 2>/dev/null || true
sudo rm -f "/Library/LaunchDaemons/$PL.plist"
pkill -f macserver-panel 2>/dev/null || true
cloudflare_ready && cf_route_remove "${PANEL_SUBDOMAIN:-panel}.${DOMAIN}" 2>/dev/null || true

# 3. monitoring (Beszel hub)
log "removing monitoring (Beszel hub)…"
sudo launchctl bootout system/io.macmultiserver.beszel 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/io.macmultiserver.beszel.plist
pkill -x beszel 2>/dev/null || true
cloudflare_ready && cf_route_remove "${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN}" 2>/dev/null || true

# 3b. sweep the DOMAIN clean — remove any leftover panel./monitor./vpsN. records
#     (tunnel ingress + DNS), preserving ssh.$DOMAIN and everything else.
if cloudflare_ready; then log "sweeping domain (Cloudflare) clean…"; cf_sweep_platform || warn "domain sweep incomplete"; fi

# 4. state (VPS metadata + panel admin login)
rm -rf "$STATE_DIR" && ok "state wiped (VPS metadata + panel login)"

# 5. --purge extras
if [ "$PURGE" = 1 ]; then
  log "purge: cached base images + Beszel hub data + DNS helper…"
  tart list 2>/dev/null | awk '/OCI/{print $2}' | while read -r img; do tart delete "$img" 2>/dev/null && echo "  removed image $img"; done
  rm -rf "$HOME/.beszel" && ok "Beszel hub data removed (~/.beszel)"
  sudo bash -c 'launchctl bootout system/io.macmultiserver.dns 2>/dev/null; rm -f /Library/LaunchDaemons/io.macmultiserver.dns.plist' 2>/dev/null && ok "DNS helper daemon removed"
fi

echo
ok "uninstall complete — no VPS, no panel, no monitoring, no state."
echo "  Left in place (remove yourself if you want):"
echo "    brew uninstall hudochenkov/sshpass/sshpass   # first-login helper"
echo "    brew uninstall cirruslabs/cli/tart           # the hypervisor"
echo "    # NOT cloudflared — it runs your SSH tunnel (kurnia-mac). Remove only if you're sure."
echo "    # Beszel hub binary lives in ~/.beszel (removed by --purge)."
echo "  Finally:  rm -rf \"$ROOT_DIR\"                  # the repo folder itself"
