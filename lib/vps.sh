#!/usr/bin/env bash
# vps.sh — the core VPS lifecycle (deploy / destroy) as functions.
# Used by both `mms` (CLI) and the control-plane panel. Requires common.sh + cloudflare.sh.

_launch_label(){ echo "io.macmultiserver.$1"; }
_launch_plist(){ echo "$HOME/Library/LaunchAgents/$(_launch_label "$1").plist"; }

# Resolve tart's binary with an absolute-path fallback — LaunchAgents (watchdog, per-VPS
# agents) run with a minimal PATH where a bare `tart` may not be found.
_tart_bin(){
  local t; t="$(command -v tart 2>/dev/null || true)"
  if [ -z "$t" ]; then for c in /opt/homebrew/bin/tart /usr/local/bin/tart; do
    [ -x "$c" ] && { t="$c"; break; }; done; fi
  echo "$t"
}

# Set the `status` field inside STATE_DIR/<name>.json, preserving every other field
# (read-modify-write via python3). Used by the lifecycle fns and the watchdog.
_vps_set_status(){ # <name> <status>
  local f="$STATE_DIR/$1.json"
  [ -f "$f" ] || return 0
  python3 - "$f" "$2" >/dev/null 2>&1 <<'PY' || true
import json,sys
f,st=sys.argv[1],sys.argv[2]
try:
    d=json.load(open(f))
except Exception:
    sys.exit(0)
d["status"]=st
json.dump(d,open(f,"w"))
PY
}

# run a VM persistently via launchd (survives reboot); fall back to nohup.
_vps_run() {
  local name="$1" label plist tart; label="$(_launch_label "$name")"; plist="$(_launch_plist "$name")"
  tart="$(_tart_bin)"
  cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>$tart</string><string>run</string><string>--no-graphics</string><string>$name</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/$label.log</string>
  <key>StandardErrorPath</key><string>/tmp/$label.log</string>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
    || { warn "launchd bootstrap failed; using nohup"; nohup "$tart" run --no-graphics "$name" >/tmp/$label.log 2>&1 & }
}

# vps_deploy <bundle> <cpu> <mem_mb> <disk_gb> [name] [label]
vps_deploy() {
  need_tool tart; need_tool sshpass
  local bundle="$1" cpu="$2" mem="$3" disk="$4" name="${5:-$(next_vps_name)}" label="${6:-}"
  valid_name "$name"
  # JSON-escape the human label (backslash, quote, strip control chars)
  label="$(printf '%s' "$label" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037')"
  [[ "$cpu" =~ ^[0-9]+$ && "$mem" =~ ^[0-9]+$ && "$disk" =~ ^[0-9]+$ ]] || die "cpu/mem/disk must be numbers"
  [ "$bundle" = blank ] || [ -d "$TEMPLATES_DIR/$bundle" ] || die "unknown bundle: $bundle"
  [ -f "$VPS_SSH_PUBKEY" ] || die "no ssh pubkey at $VPS_SSH_PUBKEY (set VPS_SSH_PUBKEY in .env)"
  local KEY; KEY="$(cat "$VPS_SSH_PUBKEY")"

  log "deploying $name ($bundle · ${cpu}vCPU · ${mem}MB · ${disk}GB)"
  tart clone "$VPS_BASE_IMAGE" "$name"
  tart set "$name" --cpu "$cpu" --memory "$mem" --disk-size "$disk"
  _vps_run "$name"; ok "VM running (persistent)"

  log "waiting for DHCP lease…"
  local ip=""; for _ in $(seq 1 40); do ip="$(tart ip "$name" 2>/dev/null || true)"; [ -n "$ip" ] && break; sleep 3; done
  [ -n "$ip" ] || die "no IP after 120s — is pf allowing DHCP? (./mms pf-fix, docs/networking.md)"
  ok "IP: $ip"

  local O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
  for _ in $(seq 1 10); do sshpass -p admin ssh $O -o PreferredAuthentications=password admin@"$ip" true 2>/dev/null && break; sleep 3; done
  sshpass -p admin ssh $O -o PreferredAuthentications=password admin@"$ip" \
    "umask 077; mkdir -p ~/.ssh; grep -qxF '$KEY' ~/.ssh/authorized_keys 2>/dev/null || printf '%s\n' '$KEY' >> ~/.ssh/authorized_keys" \
    || die "key injection failed"
  ok "SSH key installed"

  local app_port=""
  if [ "$bundle" != blank ] && [ -f "$TEMPLATES_DIR/$bundle/install.sh" ]; then
    log "installing bundle: $bundle…"
    # pass the *_INSTALL_URL vars from .env into the guest so bundles aren't hardcoded
    local envpfx=""; while IFS='=' read -r k v; do envpfx+="$k='$v' "; done < <(env | grep -E '^[A-Z_]+_INSTALL_URL=')
    ssh $O admin@"$ip" "$envpfx bash -s" < "$TEMPLATES_DIR/$bundle/install.sh" || warn "bundle install returned non-zero"
    [ -f "$TEMPLATES_DIR/$bundle/port" ] && app_port="$(cat "$TEMPLATES_DIR/$bundle/port")"
    ok "bundle $bundle installed"
  fi

  # monitoring: install the Beszel agent (reports out to the hub over the bridge). Optional.
  if [ -n "${BESZEL_KEY:-}" ] && [ -n "${BESZEL_TOKEN:-}" ]; then
    log "installing monitoring agent…"
    ssh $O admin@"$ip" "curl -sL https://get.beszel.dev -o /tmp/bza.sh && chmod +x /tmp/bza.sh && sudo /tmp/bza.sh -k '${BESZEL_KEY}' -t '${BESZEL_TOKEN}' -url '${BESZEL_HUB_URL:-http://192.168.64.1:8090}' </dev/null" >/dev/null 2>&1 \
      && ok "monitoring agent reporting to hub" || warn "beszel agent install skipped/failed"
  fi

  # SSH over the domain (Cloudflare tunnel) — tenants reach the VPS by name, never by IP.
  local ssh_host=""
  if cloudflare_ready; then
    ssh_host="$(vps_hostname "$name")"
    cf_ssh_route_add "$ssh_host" "$ip" || { warn "cloudflare ssh route failed"; ssh_host=""; }
  fi

  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/$name.json" <<JSON
{ "name":"$name","label":"$label","bundle":"$bundle","status":"running","cpu":$cpu,"mem_mb":$mem,"disk_gb":$disk,
  "ip":"$ip","app_port":"$app_port","hostname":"","ssh_host":"$ssh_host","created":"$(date -u +%FT%TZ)" }
JSON

  echo
  echo "  ✓ $name  ● running  ·  Ubuntu · ${cpu}vCPU/${mem}MB/${disk}GB · $bundle"
  echo "    IP (host-side): $ip"
  if [ -n "$ssh_host" ]; then echo "    SSH: ssh admin@$ssh_host   (tenant needs cloudflared + ProxyCommand — shown in panel)"
  else echo "    SSH: ssh admin@$ip   (no domain — set Cloudflare keys in .env)"; fi
  echo "    Manage/terminal: https://${PANEL_SUBDOMAIN:-panel}.${DOMAIN}/vps/$name"
  echo "    Destroy: ./mms destroy $name"
}

# vps_destroy <name>
vps_destroy() {
  local name="$1"; valid_name "$name"; need_tool tart
  local label; label="$(_launch_label "$name")"
  log "destroying $name…"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  pkill -f "tart run --no-graphics $name" 2>/dev/null || true
  rm -f "$(_launch_plist "$name")"
  tart stop "$name" 2>/dev/null || true
  cloudflare_ready && cf_route_remove "$(vps_hostname "$name")" 2>/dev/null || true
  tart delete "$name" 2>/dev/null && ok "VM deleted" || warn "tart delete: nothing to remove"
  rm -f "$STATE_DIR/$name.json"
  ok "$name destroyed (no residue)"
}

# ── lifecycle: restart / stop / start ────────────────────────
# These drive the per-VPS LaunchAgent (io.macmultiserver.<name>) in the gui/$(id -u)
# domain, so launchctl works without sudo. tart is resolved with an absolute-path fallback.

# vps_restart <name> — graceful tart stop, then kickstart the LaunchAgent (SIGKILL+relaunch
# of `tart run`). KeepAlive stays intact for the normal case.
vps_restart(){
  local name="$1"; valid_name "$name"
  local label tart; label="$(_launch_label "$name")"; tart="$(_tart_bin)"
  log "restarting $name…"
  [ -n "$tart" ] && "$tart" stop "$name" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null \
    || warn "kickstart failed for $label (agent not bootstrapped?)"
  _vps_set_status "$name" "running"
  ok "$name restarted"
}

# vps_stop <name> — bootout the LaunchAgent (so KeepAlive won't relaunch) then stop the VM.
# The plist is kept so vps_start can bring it back.
vps_stop(){
  local name="$1"; valid_name "$name"
  local label tart; label="$(_launch_label "$name")"; tart="$(_tart_bin)"
  log "stopping $name…"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  [ -n "$tart" ] && "$tart" stop "$name" >/dev/null 2>&1 || true
  _vps_set_status "$name" "stopped"
  ok "$name stopped"
}

# vps_start <name> — re-bootstrap the existing plist (fall back to _vps_run if it's gone).
vps_start(){
  local name="$1"; valid_name "$name"
  local label plist; label="$(_launch_label "$name")"; plist="$(_launch_plist "$name")"
  log "starting $name…"
  if [ -f "$plist" ]; then
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
      || launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null \
      || warn "start via launchd failed for $label"
  else
    warn "no plist for $name — recreating"; _vps_run "$name"
  fi
  _vps_set_status "$name" "running"
  ok "$name started"
}

# vps_list — one line per VPS
vps_list() {
  mkdir -p "$STATE_DIR"
  local any=0
  for f in "$STATE_DIR"/vps-*.json; do
    [ -e "$f" ] || continue; any=1
    local n; n="$(basename "$f" .json)"
    printf "  %-8s %s\n" "$n" "$(tart ip "$n" 2>/dev/null || echo '-')"
  done
  [ "$any" = 1 ] || echo "  (no VPS yet — ./mms deploy)"
}
