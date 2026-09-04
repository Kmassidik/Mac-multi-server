#!/usr/bin/env bash
# mms — Mac-multi-server CLI. One interface for you and the control-plane panel.
#
#   ./mms deploy [--bundle blank|openclaw] [--cpu N] [--mem MB] [--disk GB] [--name vps-N]
#   ./mms destroy <vps-N>
#   ./mms ls
#   ./mms logs <vps-N>
#   ./mms pf-fix           # allow VM DHCP through pf (needs sudo)
#   ./mms install          # full host setup
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cloudflare.sh"; . "$HERE/lib/vps.sh"

usage(){ sed -n '3,11p' "$HERE/mms" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  deploy)
    load_env
    bundle=blank cpu="$VPS_DEFAULT_CPU" mem="$VPS_DEFAULT_MEM_MB" disk="$VPS_DEFAULT_DISK_GB" name=""
    while [ $# -gt 0 ]; do case "$1" in
      --bundle) bundle="$2"; shift 2;; --cpu) cpu="$2"; shift 2;;
      --mem) mem="$2"; shift 2;; --disk) disk="$2"; shift 2;;
      --name) name="$2"; shift 2;; *) die "unknown arg: $1";;
    esac; done
    vps_deploy "$bundle" "$cpu" "$mem" "$disk" "$name" ;;
  destroy) load_env; vps_destroy "${1:?usage: mms destroy <vps-N>}" ;;
  ls|list) load_env; vps_list ;;
  logs)    tail -n 60 "/tmp/io.macmultiserver.${1:?usage: mms logs <vps-N>}.log" 2>/dev/null || echo "(no logs)";;
  pf-fix)  . "$HERE/lib/pf.sh"; [ "$(id -u)" = 0 ] || exec sudo "$0" pf-fix; pf_allow_dhcp ;;
  install) exec "$HERE/install.sh" ;;
  ""|-h|--help|help) usage 0 ;;
  *) die "unknown command: $cmd (try ./mms --help)";;
esac
