#!/usr/bin/env bash
# common.sh — shared foundation: paths, .env, logging, VPS naming/state.
# Sourced by install.sh, mms, and the lib/*.sh helpers. Never run directly.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT_DIR/lib"
STATE_DIR="$ROOT_DIR/state"
TEMPLATES_DIR="$ROOT_DIR/templates"
ENV_FILE="$ROOT_DIR/.env"

# ── logging ──────────────────────────────────────────────────
_c(){ printf '\033[%sm' "$1"; }; _r(){ printf '\033[0m'; }
log()  { printf '%s==>%s %s\n' "$(_c 34)" "$(_r)" "$*"; }
ok()   { printf '%s ✓ %s%s\n' "$(_c 32)" "$*" "$(_r)"; }
warn() { printf '%s ! %s%s\n' "$(_c 33)" "$*" "$(_r)"; }
die()  { printf '%s ✗ %s%s\n' "$(_c 31)" "$*" "$(_r)" >&2; exit 1; }

# ── .env ─────────────────────────────────────────────────────
load_env() {
  [ -f "$ENV_FILE" ] || die ".env not found — run: cp .env.example .env  then edit it."
  set -a; . "$ENV_FILE"; set +a
  : "${VPS_DEFAULT_CPU:=2}" "${VPS_DEFAULT_MEM_MB:=4096}" "${VPS_DEFAULT_DISK_GB:=40}"
  : "${VPS_BASE_IMAGE:=ghcr.io/cirruslabs/ubuntu:latest}"
  : "${VPS_SUBDOMAIN_PATTERN:=vps{n}}" "${VPS_NET_CIDR:=192.168.64.0/24}"
  : "${VPS_SSH_PUBKEY:=$HOME/.ssh/id_ed25519.pub}"
}
require_env(){ for v in "$@"; do [ -n "${!v:-}" ] || die ".env missing required key: $v"; done; }
cloudflare_ready(){ [ -n "${DOMAIN:-}" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_TUNNEL_ID:-}" ]; }

# ── tools ────────────────────────────────────────────────────
need_tool(){ command -v "$1" >/dev/null 2>&1 || die "missing tool: $1 (run ./install.sh)"; }

# ── VPS naming / state ───────────────────────────────────────
valid_name(){ [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid name: $1"; }

next_vps_name() {
  mkdir -p "$STATE_DIR"; local n=1
  while [ -e "$STATE_DIR/vps-$n.json" ] || tart list 2>/dev/null | grep -qw "vps-$n"; do n=$((n+1)); done
  echo "vps-$n"
}
vps_subdomain(){ local num="${1##*-}"; echo "${VPS_SUBDOMAIN_PATTERN/\{n\}/$num}"; }   # vps-7 -> vps7
vps_hostname(){ echo "$(vps_subdomain "$1").${DOMAIN}"; }
