#!/usr/bin/env bash
# install.sh — 1-click host setup for Mac-multi-server. Idempotent; safe to re-run.
#
#   git clone github.com/Kmassidik/Mac-multi-server && cd Mac-multi-server
#   cp .env.example .env      # fill DOMAIN + Cloudflare token
#   ./install.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/pf.sh"; . "$HERE/lib/cloudflare.sh"

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || die "Apple Silicon macOS only"

# 1. .env
if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"; chmod 600 "$ENV_FILE"
  warn "created .env — edit it (DOMAIN, Cloudflare token) then re-run ./install.sh"; exit 1
fi
chmod 600 "$ENV_FILE"; load_env; ok ".env loaded"

# 2. tools
command -v brew >/dev/null || die "Homebrew required: https://brew.sh"
log "installing tools (tart, sshpass, cloudflared, netdata)…"
brew trust cirruslabs/cli >/dev/null 2>&1 || true
brew trust hudochenkov/sshpass >/dev/null 2>&1 || true
brew list tart        >/dev/null 2>&1 || brew install cirruslabs/cli/tart
brew list sshpass     >/dev/null 2>&1 || brew install hudochenkov/sshpass/sshpass
brew list cloudflared >/dev/null 2>&1 || brew install cloudflared
brew list netdata     >/dev/null 2>&1 || brew install netdata
ok "tools: $(tart --version 2>/dev/null)"

# 3. pf: allow VM DHCP  (the #1 gotcha — docs/networking.md)
log "ensuring pf allows VM DHCP…"; sudo bash -c "source '$LIB_DIR/common.sh'; source '$LIB_DIR/pf.sh'; pf_allow_dhcp" || warn "pf DHCP fix skipped"

# 4. DHCP lease (many-VM friendly)
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist \
  bootpd -dict DHCPLeaseTimeSecs -int 600 2>/dev/null && ok "DHCP lease → 600s" || true

# 5. control plane (login + dashboard): build → launchd → route panel.$DOMAIN
if [ -f "$ROOT_DIR/control-plane/Package.swift" ]; then
  log "building control plane…"; ( cd "$ROOT_DIR/control-plane" && swift build -c release )
  local_bin="$ROOT_DIR/control-plane/.build/release/macserver-panel"
  label=io.macmultiserver.panel; plist="$HOME/Library/LaunchAgents/$label.plist"
  cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$local_bin</string><string>--port</string><string>${PANEL_PORT:-8088}</string></array>
  <key>WorkingDirectory</key><string>$ROOT_DIR</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/$label.log</string><key>StandardErrorPath</key><string>/tmp/$label.log</string>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || warn "panel launchd bootstrap failed"
  ok "control plane on 127.0.0.1:${PANEL_PORT:-8088}"
  cloudflare_ready && cf_route_add "${PANEL_SUBDOMAIN:-panel}.${DOMAIN}" 127.0.0.1 "${PANEL_PORT:-8088}" || true
fi

# 6. monitoring (Netdata) → route monitor.$DOMAIN
log "starting monitoring (Netdata)…"; brew services start netdata >/dev/null 2>&1 || true
cloudflare_ready && cf_route_add "${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN}" 127.0.0.1 19999 || true

echo; ok "install complete."
echo "  panel:      https://${PANEL_SUBDOMAIN:-panel}.${DOMAIN:-<domain>}"
echo "  monitoring: https://${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN:-<domain>}"
echo "  deploy:     ./mms deploy --bundle openclaw"
