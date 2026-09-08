#!/usr/bin/env bash
# selftest.sh — a fast, mostly read-only smoke test of the platform's happy path.
# Run it by hand before/after a deploy: `./mms selftest` (add --full for a real
# deploy→destroy round-trip). It catches "did I break the basics" without CI/CD.
# Requires common.sh + vps.sh + watchdog.sh (sourced by mms). Never run directly.

# ── tiny check harness ───────────────────────────────────────
# Each check reports pass/fail/skip and tallies; nothing here may abort under set -e,
# so every probe is wrapped in an `if`. selftest() returns non-zero iff something FAILED.
_st_pass=0; _st_fail=0; _st_skip=0
_st_ok()   { printf '  %s✓%s %s\n'        "$(_c 32)" "$(_r)" "$*"; _st_pass=$((_st_pass+1)); }
_st_no()   { printf '  %s✗%s %s\n'        "$(_c 31)" "$(_r)" "$*"; _st_fail=$((_st_fail+1)); }
_st_skip() { printf '  %s–%s %s %s(skip)%s\n' "$(_c 33)" "$(_r)" "$*" "$(_c 90)" "$(_r)"; _st_skip=$((_st_skip+1)); }
_st_head() { printf '\n%s%s%s\n' "$(_c 1)" "$*" "$(_r)"; }

# json field reader shared by the state checks (empty if unreadable/missing).
_st_json(){ python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2],""))
except Exception: print("")' "$1" "$2" 2>/dev/null || echo ""; }

selftest() {
  local full=0
  [ "${1:-}" = "--full" ] && full=1
  load_env

  printf '%sMac-multi-server selftest%s  (%s)\n' "$(_c 1)" "$(_r)" "$([ "$full" = 1 ] && echo 'full: incl. deploy round-trip' || echo 'quick; --full adds a deploy round-trip')"

  # ── host tools ─────────────────────────────────────────────
  _st_head "Host tools"
  local t
  for t in tart sshpass cloudflared ssh python3 curl; do
    if command -v "$t" >/dev/null 2>&1; then _st_ok "$t found"; else _st_no "$t MISSING (run ./install.sh)"; fi
  done

  # ── config / paths ─────────────────────────────────────────
  _st_head "Config & paths"
  if [ -f "$ENV_FILE" ]; then _st_ok ".env present"; else _st_no ".env missing (cp .env.example .env)"; fi
  # the classic footgun: launchd can't run binaries out of a TCC-protected dir.
  case "$ROOT_DIR" in
    "$HOME"/Desktop/*|"$HOME"/Documents/*|"$HOME"/Downloads/*)
      _st_no "repo is in a TCC path ($ROOT_DIR) — launchd services will hang; move to ~/mac-multi-server" ;;
    *) _st_ok "repo not in a TCC path" ;;
  esac
  if [ -f "$VPS_SSH_PUBKEY" ]; then _st_ok "ssh pubkey present ($VPS_SSH_PUBKEY)"; else _st_no "no ssh pubkey at $VPS_SSH_PUBKEY (set VPS_SSH_PUBKEY)"; fi
  if mkdir -p "$STATE_DIR" 2>/dev/null && [ -w "$STATE_DIR" ]; then _st_ok "state dir writable"; else _st_no "state dir not writable ($STATE_DIR)"; fi
  # VM storage volume reachable (external SSD may be unplugged)
  local vmroot="${TART_HOME:-$HOME/.tart}"
  if mkdir -p "$vmroot" 2>/dev/null && [ -d "$vmroot" ]; then _st_ok "VM storage reachable ($vmroot)"; else _st_no "VM storage unavailable ($vmroot) — external SSD unplugged?"; fi

  # ── pure functions (no VM needed) ──────────────────────────
  _st_head "Core logic"
  if ( valid_name "vps-1" ) >/dev/null 2>&1; then _st_ok "valid_name accepts a good name"; else _st_no "valid_name rejected a good name"; fi
  if ( valid_name 'bad name!' ) >/dev/null 2>&1; then _st_no "valid_name accepted a bad name"; else _st_ok "valid_name rejects a bad name"; fi
  local sub; sub="$(vps_subdomain vps-7 2>/dev/null || true)"
  if [ -n "$sub" ] && [ "$sub" != "vps-7" ]; then _st_ok "vps_subdomain maps vps-7 → $sub"; else _st_no "vps_subdomain didn't map (pattern=$VPS_SUBDOMAIN_PATTERN)"; fi
  local nn; nn="$(next_vps_name 2>/dev/null || true)"
  if ( valid_name "$nn" ) >/dev/null 2>&1; then _st_ok "next_vps_name → $nn"; else _st_no "next_vps_name produced an invalid name ('$nn')"; fi

  # ── state integrity ────────────────────────────────────────
  _st_head "State files"
  local f n status bad=0 count=0
  for f in "$STATE_DIR"/vps-*.json; do
    [ -e "$f" ] || continue
    count=$((count+1)); n="$(basename "$f" .json)"
    status="$(_st_json "$f" status)"
    if [ -z "$(_st_json "$f" name)" ] || [ -z "$status" ]; then
      _st_no "$n: invalid/incomplete JSON (name/status)"; bad=1
    fi
  done
  if [ "$count" = 0 ]; then _st_skip "no VPS deployed yet"
  elif [ "$bad" = 0 ]; then _st_ok "$count state file(s) valid"; fi
  if mms_out="$(vps_list 2>&1)"; then _st_ok "vps_list runs clean"; else _st_no "vps_list errored"; fi

  # ── services / liveness ────────────────────────────────────
  _st_head "Services"
  local port="${PANEL_PORT:-8088}" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://127.0.0.1:$port/" 2>/dev/null || echo 000)"
  case "$code" in
    200|302|401|403) _st_ok "panel responds on 127.0.0.1:$port (HTTP $code)" ;;
    000)             _st_no "panel not responding on 127.0.0.1:$port (is the daemon loaded?)" ;;
    *)               _st_no "panel on :$port returned unexpected HTTP $code" ;;
  esac
  if [ -f "/Library/LaunchDaemons/io.macmultiserver.panel.plist" ]; then _st_ok "panel LaunchDaemon plist installed"; else _st_skip "panel plist not found (dev checkout, not installed?)"; fi
  if launchctl list 2>/dev/null | grep -q "io.macmultiserver.watchdog"; then _st_ok "watchdog LaunchAgent loaded"; else _st_no "watchdog LaunchAgent not loaded (self-healing is off)"; fi

  # ── optional integrations ──────────────────────────────────
  _st_head "Integrations"
  if cloudflare_ready; then _st_ok "Cloudflare configured (domain SSH available)"; else _st_skip "Cloudflare not configured — VPS reachable by IP only"; fi
  if [ -n "${BESZEL_ADMIN_EMAIL:-}" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "${BESZEL_HUB_URL:-http://127.0.0.1:8090}/api/health" 2>/dev/null || echo 000)"
    if [ "$code" = 200 ]; then _st_ok "Beszel hub responds (${BESZEL_HUB_URL:-http://127.0.0.1:8090})"; else _st_no "Beszel configured but hub not responding (HTTP $code)"; fi
  else _st_skip "Beszel not configured — monitoring tab will show 'not configured'"; fi

  # ── full: real deploy → destroy round-trip ─────────────────
  if [ "$full" = 1 ]; then
    _st_head "Deploy round-trip (--full)"
    local name; name="$(next_vps_name)"
    log "deploying throwaway $name (blank · 2vCPU · 1024MB · 20GB)…"
    if vps_deploy blank 2 1024 20 "$name" "selftest" >/dev/null 2>&1; then
      local st; st="$(_st_json "$STATE_DIR/$name.json" status)"
      if [ "$st" = "running" ]; then _st_ok "$name deployed and reached 'running'"; else _st_no "$name deployed but status='$st' (expected running)"; fi
    else _st_no "$name deploy failed (see: ./mms logs $name)"; fi
    log "destroying $name…"
    if vps_destroy "$name" >/dev/null 2>&1; then
      if [ ! -e "$STATE_DIR/$name.json" ]; then _st_ok "$name destroyed (no residue)"; else _st_no "$name destroy left state behind"; fi
    else _st_no "$name destroy failed — clean up manually: ./mms destroy $name"; fi
  fi

  # ── summary ────────────────────────────────────────────────
  printf '\n%s%d passed%s · %s%d failed%s · %s%d skipped%s\n' \
    "$(_c 32)" "$_st_pass" "$(_r)" \
    "$([ "$_st_fail" -gt 0 ] && _c 31 || _c 90)" "$_st_fail" "$(_r)" \
    "$(_c 90)" "$_st_skip" "$(_r)"
  [ "$_st_fail" = 0 ]
}
