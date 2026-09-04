#!/usr/bin/env bash
# install.sh — 1-click host setup for Mac-multi-server.
# Idempotent: safe to re-run. Installs tools, fixes pf for VM DHCP, wires the panel.
#
#   git clone … && cd Mac-multi-server
#   cp .env.example .env      # fill DOMAIN + Cloudflare token
#   ./scripts/install.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/lib.sh"

# 0. sanity
[ "$(uname -s)" = "Darwin" ] || die "macOS only"
[ "$(uname -m)" = "arm64" ]  || die "Apple Silicon (arm64) only"

# 1. .env
if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"; chmod 600 "$ENV_FILE"
  warn "created .env from template — edit it (DOMAIN, Cloudflare token) then re-run."; exit 1
fi
chmod 600 "$ENV_FILE"; load_env
ok ".env loaded"

# 2. homebrew + tools
command -v brew >/dev/null 2>&1 || die "Homebrew required: https://brew.sh"
log "installing tools (tart, sshpass, cloudflared)…"
brew trust cirruslabs/cli    >/dev/null 2>&1 || true
brew trust hudochenkov/sshpass >/dev/null 2>&1 || true
brew list tart       >/dev/null 2>&1 || brew install cirruslabs/cli/tart
brew list sshpass    >/dev/null 2>&1 || brew install hudochenkov/sshpass/sshpass
brew list cloudflared>/dev/null 2>&1 || brew install cloudflared
ok "tools present: $(tart --version 2>/dev/null)"

# 3. pf: allow VM DHCP  (the #1 gotcha — see docs/networking.md)
if [ -f /etc/pf.anchors/dalang.hardening ]; then
  log "ensuring pf allows VM DHCP…"; sudo "$HERE/pf-allow-dhcp.sh" || warn "pf DHCP fix skipped/failed — check docs/networking.md"
else
  warn "no hardened pf anchor found; if VMs get no IP, see docs/networking.md"
fi

# 4. shorten DHCP lease (many-VM friendly)
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist \
  bootpd -dict DHCPLeaseTimeSecs -int 600 2>/dev/null && ok "DHCP lease set to 600s" || true

# 5. control plane (login + dashboard) — build, run as a service, expose via Cloudflare
if [ -f "$ROOT_DIR/control-plane/Package.swift" ]; then
  log "building control plane (login + dashboard)…"
  ( cd "$ROOT_DIR/control-plane" && swift build -c release )
  BIN="$ROOT_DIR/control-plane/.build/release/macserver-panel"
  LABEL=io.macmultiserver.panel
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string><string>--port</string><string>${PANEL_PORT:-8088}</string></array>
  <key>WorkingDirectory</key><string>$ROOT_DIR</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/$LABEL.log</string><key>StandardErrorPath</key><string>/tmp/$LABEL.log</string>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || warn "panel launchd bootstrap failed"
  ok "control plane running on 127.0.0.1:${PANEL_PORT:-8088}"
  if cloudflare_ready; then
    "$HERE/cloudflare-route.sh" add "${PANEL_SUBDOMAIN:-panel}.${DOMAIN}" 127.0.0.1 "${PANEL_PORT:-8088}" \
      && ok "panel: https://${PANEL_SUBDOMAIN:-panel}.${DOMAIN}" || warn "panel cloudflare route failed"
  fi
else
  warn "control-plane Swift target not present yet — engine scripts are usable via CLI"
fi

# 6. monitoring (Netdata) — install + expose
log "setting up monitoring…"; "$HERE/setup-monitoring.sh" || warn "monitoring setup skipped/failed"

# 7. cloudflare summary
if cloudflare_ready; then ok "Cloudflare config present (DOMAIN=$DOMAIN)"
else warn "Cloudflare not fully configured in .env — public routing skipped (see docs/setup.md)"; fi

echo
ok "install complete."
echo "  panel:      https://${PANEL_SUBDOMAIN:-panel}.${DOMAIN:-<your-domain>}"
echo "  monitoring: https://${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN:-<your-domain>}"
echo "  deploy CLI: ./scripts/deploy-vps.sh --bundle openclaw"
