#!/usr/bin/env bash
# destroy-vps.sh — tear a VPS down cleanly, no residue.
#
#   ./scripts/destroy-vps.sh <vps-N>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/lib.sh"
load_env; need_tool tart

NAME="${1:-}"; [ -n "$NAME" ] || die "usage: destroy-vps.sh <vps-N>"
valid_name "$NAME"

LABEL="io.macmultiserver.$NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# 1. stop + remove launchd runner
log "stopping $NAME…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "tart run --no-graphics $NAME" 2>/dev/null || true
rm -f "$PLIST"
tart stop "$NAME" 2>/dev/null || true

# 2. cloudflare route
if cloudflare_ready; then
  HN="$(vps_hostname "$NAME")"
  "$HERE/cloudflare-route.sh" remove "$HN" 2>/dev/null || warn "cloudflare route removal skipped"
fi

# 3. delete the VM + state
tart delete "$NAME" 2>/dev/null && ok "VM deleted" || warn "tart delete: nothing to remove"
rm -f "$STATE_DIR/$NAME.json"

ok "$NAME destroyed (no residue)"
