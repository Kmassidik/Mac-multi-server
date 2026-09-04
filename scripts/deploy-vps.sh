#!/usr/bin/env bash
# deploy-vps.sh — provision one real VPS (Tart Linux VM) end-to-end.
#
#   ./scripts/deploy-vps.sh [--bundle blank|openclaw] [--cpu N] [--mem MB] [--disk GB] [--name vps-N]
#
# Flow: clone → set specs → launchd run (persistent) → wait IP → inject key
#       → run bundle install → cloudflare route → write state → print details.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/lib.sh"
load_env
need_tool tart; need_tool sshpass

# ── args ─────────────────────────────────────────────────────
BUNDLE=blank; CPU="$VPS_DEFAULT_CPU"; MEM="$VPS_DEFAULT_MEM_MB"; DISK="$VPS_DEFAULT_DISK_GB"; NAME=""
while [ $# -gt 0 ]; do case "$1" in
  --bundle) BUNDLE="$2"; shift 2;;
  --cpu)    CPU="$2";    shift 2;;
  --mem)    MEM="$2";    shift 2;;
  --disk)   DISK="$2";   shift 2;;
  --name)   NAME="$2";   shift 2;;
  *) die "unknown arg: $1";;
esac; done
[ -n "$NAME" ] || NAME="$(next_vps_name)"
valid_name "$NAME"
[[ "$CPU" =~ ^[0-9]+$ && "$MEM" =~ ^[0-9]+$ && "$DISK" =~ ^[0-9]+$ ]] || die "cpu/mem/disk must be numbers"
[ -d "$ROOT_DIR/templates/$BUNDLE" ] || [ "$BUNDLE" = blank ] || die "unknown bundle: $BUNDLE (see templates/)"

# ssh key to authorize on the VPS
PUBKEY="${VPS_SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
[ -f "$PUBKEY" ] && KEY="$(cat "$PUBKEY")" || die "no ssh pubkey at $PUBKEY (set VPS_SSH_PUBKEY in .env)"

log "deploying $NAME  ($BUNDLE · ${CPU}vCPU · ${MEM}MB · ${DISK}GB)"

# ── 1. clone + specs ─────────────────────────────────────────
log "cloning base image…"; tart clone "$VPS_BASE_IMAGE" "$NAME"
tart set "$NAME" --cpu "$CPU" --memory "$MEM" --disk "$DISK"
ok "image ready"

# ── 2. persistent run via launchd ────────────────────────────
LABEL="io.macmultiserver.$NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TART_BIN="$(command -v tart)"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$TART_BIN</string><string>run</string><string>--no-graphics</string><string>$NAME</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/$LABEL.log</string>
  <key>StandardErrorPath</key><string>/tmp/$LABEL.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || { warn "launchd bootstrap failed; falling back to nohup"; nohup "$TART_BIN" run --no-graphics "$NAME" >/tmp/$LABEL.log 2>&1 & }
ok "VM running (persistent)"

# ── 3. wait for IP ───────────────────────────────────────────
log "waiting for DHCP lease…"
IP=""; for i in $(seq 1 40); do IP="$(tart ip "$NAME" 2>/dev/null || true)"; [ -n "$IP" ] && break; sleep 3; done
[ -n "$IP" ] || die "no IP after 120s — is pf allowing DHCP? (./scripts/pf-allow-dhcp.sh, docs/networking.md)"
ok "IP: $IP"

# ── 4. inject key (first login admin/admin → key-only) ───────
log "authorizing your SSH key…"
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
for i in $(seq 1 10); do sshpass -p admin ssh $SSHOPT -o PreferredAuthentications=password admin@"$IP" true 2>/dev/null && break; sleep 3; done
sshpass -p admin ssh $SSHOPT -o PreferredAuthentications=password admin@"$IP" \
  "umask 077; mkdir -p ~/.ssh; grep -qxF '$KEY' ~/.ssh/authorized_keys 2>/dev/null || printf '%s\n' '$KEY' >> ~/.ssh/authorized_keys" \
  || die "key injection failed"
ok "key installed (key-based SSH ready)"

# ── 5. bundle install ────────────────────────────────────────
APP_PORT=""
if [ "$BUNDLE" != blank ] && [ -f "$ROOT_DIR/templates/$BUNDLE/install.sh" ]; then
  log "installing bundle: $BUNDLE…"
  ssh $SSHOPT admin@"$IP" 'bash -s' < "$ROOT_DIR/templates/$BUNDLE/install.sh" || warn "bundle install returned non-zero"
  [ -f "$ROOT_DIR/templates/$BUNDLE/port" ] && APP_PORT="$(cat "$ROOT_DIR/templates/$BUNDLE/port")"
  ok "bundle $BUNDLE installed"
fi

# ── 6. cloudflare route (if configured + app present) ────────
HOSTNAME_PUB=""
if cloudflare_ready && [ -n "$APP_PORT" ]; then
  HOSTNAME_PUB="$(vps_hostname "$NAME")"
  log "routing $HOSTNAME_PUB → $IP:$APP_PORT via Cloudflare…"
  "$HERE/cloudflare-route.sh" add "$HOSTNAME_PUB" "$IP" "$APP_PORT" && ok "public: https://$HOSTNAME_PUB" || warn "cloudflare route failed"
fi

# ── 7. record state ──────────────────────────────────────────
state_write "$NAME" <<JSON
{
  "name": "$NAME", "bundle": "$BUNDLE", "status": "running",
  "cpu": $CPU, "mem_mb": $MEM, "disk_gb": $DISK,
  "ip": "$IP", "app_port": "${APP_PORT}",
  "hostname": "${HOSTNAME_PUB}",
  "created": "$(date -u +%FT%TZ)"
}
JSON

# ── 8. details card ──────────────────────────────────────────
echo
echo "┌─────────────────────────────────────────────"
printf "│  %-8s   ● running\n" "$NAME"
printf "│  Ubuntu 24.04 · %s vCPU · %s MB · %s GB\n" "$CPU" "$MEM" "$DISK"
printf "│  IP:    %s\n" "$IP"
[ -n "$HOSTNAME_PUB" ] && printf "│  App:   https://%s\n" "$HOSTNAME_PUB"
printf "│  SSH:   ssh -J %s admin@%s\n" "${PANEL_SSH_JUMP:-<mac>}" "$IP"
echo "│  Destroy: ./scripts/destroy-vps.sh $NAME"
echo "└─────────────────────────────────────────────"
