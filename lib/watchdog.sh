#!/usr/bin/env bash
# watchdog.sh — health loop for the VPS fleet.
# Runs one pass per invocation (`mms watchdog`); the LaunchAgent io.macmultiserver.watchdog
# calls it every WATCHDOG_INTERVAL seconds. Requires common.sh + vps.sh (sourced by mms).
#
# Algorithm (per running VPS):
#   probe  = tart ip resolves  AND  ssh admin@<ip> true succeeds  → healthy
#   healthy   → fails=0, status "running"
#   unhealthy → fails++  ; status "unhealthy"
#   fails >= WATCHDOG_FAIL_THRESHOLD (default 3, consecutive) → restart, UNLESS back-off tripped
#   back-off: >= WATCHDOG_MAX_RESTARTS (default 3) restarts inside WATCHDOG_BACKOFF_WINDOW
#             (default 900s) → status "flapping", do NOT restart. Counter resets when window elapses.
#   VPS whose desired state is "stopped" are skipped entirely (never probed, never restarted).

WATCHDOG_LOG="/tmp/io.macmultiserver.watchdog.log"

wd_log(){ printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$WATCHDOG_LOG" 2>/dev/null || true; }

# run a command with a timeout if one is available (LaunchAgent PATH is minimal).
_wd_run_to(){ local t="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$t" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$t" "$@"
  else "$@"; fi
}

# ── per-VPS health sidecar: STATE_DIR/<name>.health (plain key=val) ──
_health_file(){ echo "$STATE_DIR/$1.health"; }
_health_get(){ # <name> <key> <default>
  local f v=""; f="$(_health_file "$1")"
  [ -f "$f" ] && v="$(grep -E "^$2=" "$f" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  echo "${v:-$3}"
}
_health_set(){ # <name> <fails> <restarts> <window_start> <last_restart>
  local f; f="$(_health_file "$1")"
  { printf 'fails=%s\n' "$2"; printf 'restarts=%s\n' "$3"
    printf 'window_start=%s\n' "$4"; printf 'last_restart=%s\n' "$5"; } > "$f" 2>/dev/null || true
}

# read the status field out of a state file (empty if unreadable).
_wd_status(){ python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("status",""))
except Exception: print("")' "$1" 2>/dev/null || echo ""; }

# watchdog_probe <name> → 0 healthy, 1 unhealthy (no IP = unhealthy)
watchdog_probe(){
  local name="$1" ip tart; tart="$(_tart_bin)"
  [ -n "$tart" ] || { wd_log "$name probe: tart not found"; return 1; }
  ip="$(_wd_run_to 8 "$tart" ip "$name" 2>/dev/null || true)"
  [ -n "$ip" ] || return 1
  ssh -i "$HOME/.ssh/id_ed25519" -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "admin@$ip" true >/dev/null 2>&1
}

# watchdog_tick — one full pass over the fleet.
watchdog_tick(){
  mkdir -p "$STATE_DIR"
  local now threshold maxr window
  now="$(date +%s)"
  threshold="${WATCHDOG_FAIL_THRESHOLD:-3}"
  maxr="${WATCHDOG_MAX_RESTARTS:-3}"
  window="${WATCHDOG_BACKOFF_WINDOW:-900}"

  local f name status fails restarts window_start last_restart
  local any=0
  for f in "$STATE_DIR"/vps-*.json; do
    [ -e "$f" ] || continue
    any=1
    name="$(basename "$f" .json)"
    status="$(_wd_status "$f")"

    # never touch a VPS the operator deliberately Stopped.
    if [ "$status" = "stopped" ]; then wd_log "$name skip (stopped)"; continue; fi

    fails="$(_health_get "$name" fails 0)"
    restarts="$(_health_get "$name" restarts 0)"
    window_start="$(_health_get "$name" window_start "$now")"
    last_restart="$(_health_get "$name" last_restart 0)"

    # rolling window: forget restarts older than WATCHDOG_BACKOFF_WINDOW.
    if [ "$(( now - window_start ))" -ge "$window" ]; then
      [ "$restarts" -gt 0 ] && wd_log "$name back-off window elapsed — restart counter reset"
      restarts=0; window_start="$now"
    fi

    if watchdog_probe "$name"; then
      fails=0
      _health_set "$name" "$fails" "$restarts" "$window_start" "$last_restart"
      [ "$status" = "running" ] || _vps_set_status "$name" "running"
      wd_log "$name healthy (restarts=$restarts/$maxr in window)"
      continue
    fi

    # unhealthy
    fails="$(( fails + 1 ))"
    wd_log "$name unhealthy (fails=$fails/$threshold)"

    if [ "$fails" -lt "$threshold" ]; then
      _vps_set_status "$name" "unhealthy"
      _health_set "$name" "$fails" "$restarts" "$window_start" "$last_restart"
      continue
    fi

    # threshold reached → restart unless back-off tripped.
    if [ "$restarts" -ge "$maxr" ]; then
      _vps_set_status "$name" "flapping"
      _health_set "$name" "$fails" "$restarts" "$window_start" "$last_restart"
      wd_log "$name FLAPPING — back-off tripped ($restarts restarts in ${window}s); NOT restarting"
      continue
    fi

    _vps_set_status "$name" "restarting"
    wd_log "$name RESTARTING (attempt $(( restarts + 1 ))/$maxr)"
    vps_restart "$name" >>"$WATCHDOG_LOG" 2>&1 || wd_log "$name restart command returned non-zero"
    restarts="$(( restarts + 1 ))"
    last_restart="$now"
    fails=0
    _health_set "$name" "$fails" "$restarts" "$window_start" "$last_restart"
  done
  [ "$any" = 1 ] || wd_log "no VPS to check"
}
