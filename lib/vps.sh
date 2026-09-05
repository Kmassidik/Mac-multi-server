#!/usr/bin/env bash
# vps.sh — the core VPS lifecycle (deploy / destroy) as functions.
# Used by both `mms` (CLI) and the control-plane panel. Requires common.sh + cloudflare.sh.

_launch_label(){ echo "io.macmultiserver.$1"; }
_launch_plist(){ echo "$HOME/Library/LaunchAgents/$(_launch_label "$1").plist"; }

# run a VM persistently via launchd (survives reboot); fall back to nohup.
_vps_run() {
  local name="$1" label plist tart; label="$(_launch_label "$name")"; plist="$(_launch_plist "$name")"
  tart="$(command -v tart)"
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

# vps_deploy <bundle> <cpu> <mem_mb> <disk_gb> [name]
vps_deploy() {
  need_tool tart; need_tool sshpass
  local bundle="$1" cpu="$2" mem="$3" disk="$4" name="${5:-$(next_vps_name)}"
  valid_name "$name"
  [[ "$cpu" =~ ^[0-9]+$ && "$mem" =~ ^[0-9]+$ && "$disk" =~ ^[0-9]+$ ]] || die "cpu/mem/disk must be numbers"
  [ "$bundle" = blank ] || [ -d "$TEMPLATES_DIR/$bundle" ] || die "unknown bundle: $bundle"
  [ -f "$VPS_SSH_PUBKEY" ] || die "no ssh pubkey at $VPS_SSH_PUBKEY (set VPS_SSH_PUBKEY in .env)"
  local KEY; KEY="$(cat "$VPS_SSH_PUBKEY")"

  log "deploying $name ($bundle · ${cpu}vCPU · ${mem}MB · ${disk}GB)"
  tart clone "$VPS_BASE_IMAGE" "$name"
  tart set "$name" --cpu "$cpu" --memory "$mem" --disk "$disk"
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

  local host=""
  if cloudflare_ready && [ -n "$app_port" ]; then
    host="$(vps_hostname "$name")"; cf_route_add "$host" "$ip" "$app_port" || warn "cloudflare route failed"
  fi

  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/$name.json" <<JSON
{ "name":"$name","bundle":"$bundle","status":"running","cpu":$cpu,"mem_mb":$mem,"disk_gb":$disk,
  "ip":"$ip","app_port":"$app_port","hostname":"$host","created":"$(date -u +%FT%TZ)" }
JSON

  echo
  echo "  ✓ $name  ● running  ·  Ubuntu · ${cpu}vCPU/${mem}MB/${disk}GB · $bundle"
  echo "    IP:  $ip"
  [ -n "$host" ] && echo "    App: https://$host"
  echo "    SSH: ssh -J ${PANEL_SSH_JUMP:-<mac>} admin@$ip"
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
