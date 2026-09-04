#!/usr/bin/env bash
# lib.sh — shared helpers. Source this from the other scripts.
# Loads .env, provides logging, validation, and VPS/state helpers.

set -euo pipefail

# ── paths ────────────────────────────────────────────────────
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$LIB_DIR/.." && pwd)"
STATE_DIR="$ROOT_DIR/state"
ENV_FILE="$ROOT_DIR/.env"

# ── logging ──────────────────────────────────────────────────
c_reset=$'\033[0m'; c_blue=$'\033[34m'; c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'
log()  { printf '%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '%s ✓ %s%s\n' "$c_green" "$*" "$c_reset"; }
warn() { printf '%s ! %s%s\n' "$c_yellow" "$*" "$c_reset"; }
die()  { printf '%s ✗ %s%s\n' "$c_red" "$*" "$c_reset" >&2; exit 1; }

# ── .env ─────────────────────────────────────────────────────
load_env() {
  [ -f "$ENV_FILE" ] || die ".env not found. Run: cp .env.example .env  then edit it."
  set -a; . "$ENV_FILE"; set +a
  # defaults (in case an older .env is missing keys)
  : "${VPS_DEFAULT_CPU:=2}"
  : "${VPS_DEFAULT_MEM_MB:=4096}"
  : "${VPS_DEFAULT_DISK_GB:=40}"
  : "${VPS_BASE_IMAGE:=ghcr.io/cirruslabs/ubuntu:latest}"
  : "${VPS_SUBDOMAIN_PATTERN:=vps{n}}"
  : "${VPS_NET_CIDR:=192.168.64.0/24}"
}

require_env() { for v in "$@"; do [ -n "${!v:-}" ] || die ".env missing required key: $v"; done; }

cloudflare_ready() { [ -n "${DOMAIN:-}" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; }

# ── tart / tools ─────────────────────────────────────────────
need_tool() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1 (run ./scripts/install.sh)"; }

# ── VPS naming / state ───────────────────────────────────────
mkdir_state() { mkdir -p "$STATE_DIR"; }

# next free vps name: vps-1, vps-2, ...
next_vps_name() {
  mkdir_state
  local n=1
  while [ -e "$STATE_DIR/vps-$n.json" ] || tart list 2>/dev/null | grep -qw "vps-$n"; do n=$((n+1)); done
  echo "vps-$n"
}

# subdomain for a vps name (vps-7 -> vps7 via pattern vps{n})
vps_subdomain() { # $1 = vps-N
  local num="${1##*-}"
  echo "${VPS_SUBDOMAIN_PATTERN/\{n\}/$num}"
}

vps_hostname() { echo "$(vps_subdomain "$1").${DOMAIN}"; }  # $1 = vps-N

# safe name check (no shell/tart injection)
valid_name() { [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid name: $1"; }

state_write() { # $1=name  (reads KEY=VAL pairs from stdin as JSON fields)
  mkdir_state
  cat > "$STATE_DIR/$1.json"
}
