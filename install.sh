#!/usr/bin/env bash
# install.sh — 1-click host setup for Mac-multi-server. Idempotent; safe to re-run.
#
#   git clone github.com/Kmassidik/Mac-multi-server && cd Mac-multi-server
#   cp .env.example .env      # fill DOMAIN + Cloudflare token
#   ./install.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/pf.sh"; . "$HERE/lib/cloudflare.sh"

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || die "Apple Silicon macOS only"

# 0. TCC guard — launchd services CANNOT load binaries from Desktop/Documents/Downloads.
# macOS TCC blocks even root there (no Full Disk Access), so the process hangs in dyld and
# never binds. Refuse early with a clear fix instead of a mystifying 502 later.
case "$ROOT_DIR/" in
  "$HOME/Desktop/"*|"$HOME/Documents/"*|"$HOME/Downloads/"*)
    die "This repo is in a TCC-protected folder:
    $ROOT_DIR
  launchd can't run services from Desktop/Documents/Downloads. Move it out and re-run, e.g.:
    mv \"$ROOT_DIR\" ~/mac-multi-server && cd ~/mac-multi-server && ./install.sh" ;;
esac

# 1. .env
if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"; chmod 600 "$ENV_FILE"
  warn "created .env — edit it (DOMAIN, Cloudflare token) then re-run ./install.sh"; exit 1
fi
chmod 600 "$ENV_FILE"; load_env; ok ".env loaded"

# 2. tools
command -v brew >/dev/null || die "Homebrew required: https://brew.sh"
log "installing tools (tart, sshpass, cloudflared)…"
brew trust cirruslabs/cli >/dev/null 2>&1 || true
brew trust hudochenkov/sshpass >/dev/null 2>&1 || true
brew list tart        >/dev/null 2>&1 || brew install cirruslabs/cli/tart
brew list sshpass     >/dev/null 2>&1 || brew install hudochenkov/sshpass/sshpass
brew list cloudflared >/dev/null 2>&1 || brew install cloudflared
ok "tools: $(tart --version 2>/dev/null)"

# 3. pf: allow VM DHCP  (the #1 gotcha — docs/networking.md)
log "ensuring pf allows VM DHCP…"; sudo bash -c "source '$LIB_DIR/common.sh'; source '$LIB_DIR/pf.sh'; pf_allow_dhcp" || warn "pf DHCP fix skipped"

# 4. DHCP lease (many-VM friendly)
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist \
  bootpd -dict DHCPLeaseTimeSecs -int 600 2>/dev/null && ok "DHCP lease → 600s" || true

# 5. control plane (login + dashboard): build → LaunchDaemon → route panel.$DOMAIN
# A LaunchDaemon (system, runs as you) works headless — no GUI login needed — and, since the
# repo is now outside TCC folders, it can load the binary fine.
if [ -f "$ROOT_DIR/control-plane/Package.swift" ]; then
  log "building control plane…"; ( cd "$ROOT_DIR/control-plane" && swift build -c release )
  local_bin="$ROOT_DIR/control-plane/.build/release/macserver-panel"
  label=io.macmultiserver.panel; plist="/Library/LaunchDaemons/$label.plist"
  sudo bash -c "cat > '$plist' <<PL
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>$label</string>
  <key>UserName</key><string>$(id -un)</string>
  <key>ProgramArguments</key><array><string>$local_bin</string><string>--port</string><string>${PANEL_PORT:-8088}</string></array>
  <key>WorkingDirectory</key><string>$ROOT_DIR</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/$label.log</string><key>StandardErrorPath</key><string>/tmp/$label.log</string>
</dict></plist>"
  sudo launchctl bootout "system/$label" 2>/dev/null || true
  sudo launchctl bootstrap system "$plist" 2>/dev/null || warn "panel LaunchDaemon bootstrap failed"
  sleep 2
  if curl -s -o /dev/null -m 3 http://127.0.0.1:${PANEL_PORT:-8088}/; then ok "control plane live on 127.0.0.1:${PANEL_PORT:-8088}"
  else warn "panel not responding yet on ${PANEL_PORT:-8088} — check /tmp/$label.log"; fi
  cloudflare_ready && cf_route_add "${PANEL_SUBDOMAIN:-panel}.${DOMAIN}" 127.0.0.1 "${PANEL_PORT:-8088}" || true
fi

# 6. monitoring (Beszel hub) — self-hosted, own login; agents in each VPS report to it
log "installing Beszel hub…"
BZ_DIR="$HOME/.beszel"; mkdir -p "$BZ_DIR"
os=$(uname -s | tr 'A-Z' 'a-z'); arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
if [ ! -x "$BZ_DIR/beszel" ]; then
  curl -sL "https://github.com/henrygd/beszel/releases/latest/download/beszel_${os}_${arch}.tar.gz" \
    | tar -xz -O beszel > "$BZ_DIR/beszel" && chmod +x "$BZ_DIR/beszel" && ok "beszel $("$BZ_DIR/beszel" --version 2>/dev/null | awk '{print $3}')"
fi
# LaunchDaemon: hub on 0.0.0.0:8090 (pf blocks it externally; reachable by VPS on the bridge + by cloudflared on localhost)
BL=io.macmultiserver.beszel; BP="/Library/LaunchDaemons/$BL.plist"
sudo bash -c "cat > '$BP' <<PL
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>$BL</string><key>UserName</key><string>$(id -un)</string>
  <key>ProgramArguments</key><array><string>$BZ_DIR/beszel</string><string>serve</string><string>--http</string><string>0.0.0.0:8090</string></array>
  <key>WorkingDirectory</key><string>$BZ_DIR</string>
  <key>EnvironmentVariables</key><dict><key>APP_URL</key><string>https://${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN}</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/$BL.log</string><key>StandardErrorPath</key><string>/tmp/$BL.log</string>
</dict></plist>"
sudo launchctl bootout "system/$BL" 2>/dev/null || true
sudo launchctl bootstrap system "$BP" 2>/dev/null && ok "Beszel hub on 0.0.0.0:8090" || warn "Beszel hub bootstrap failed"
# create/update the hub admin from .env (skip the first-run web form)
if [ -n "${BESZEL_ADMIN_EMAIL:-}" ] && [ -n "${BESZEL_ADMIN_PASSWORD:-}" ]; then
  ( cd "$BZ_DIR" && ./beszel superuser upsert "$BESZEL_ADMIN_EMAIL" "$BESZEL_ADMIN_PASSWORD" ) >/dev/null 2>&1 \
    && ok "Beszel admin set from .env ($BESZEL_ADMIN_EMAIL)" || warn "Beszel admin upsert failed (password must be ≥8 chars)"
fi
# monitor.$DOMAIN → the hub (Beszel has its own login)
cloudflare_ready && cf_route_add "${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN}" 127.0.0.1 8090 || true
[ -z "${BESZEL_KEY:-}" ] && warn "BESZEL_KEY/BESZEL_TOKEN not set — open monitoring, create the hub admin, then copy the key + a universal token from Settings into .env so new VPS auto-report (see docs/monitoring.md)"

echo; ok "install complete."
echo "  panel:      https://${PANEL_SUBDOMAIN:-panel}.${DOMAIN:-<domain>}"
echo "  monitoring: https://${GRAFANA_SUBDOMAIN:-monitor}.${DOMAIN:-<domain>}"
echo "  deploy:     ./mms deploy --bundle openclaw"
