#!/usr/bin/env bash
# pf-allow-dhcp.sh — let Tart VMs get a DHCP lease on the NAT bridge.
#
# THE #1 GOTCHA on a hardened Mac: a default-deny pf ruleset (`block drop in quick all`)
# drops a VM's DHCP DISCOVER, because it comes from 0.0.0.0:68 → 255.255.255.255:67 and
# matches no pass rule (the subnet-pass needs a real source IP; the usual DHCP rule only
# covers the server→client direction 67→68). Result: VMs boot fine but never get an IP.
#
# Fix: allow the client→server direction (udp 68→67) BEFORE the block. Idempotent.
#
# Usage: sudo ./pf-allow-dhcp.sh [/etc/pf.anchors/<anchor>]
set -euo pipefail

ANCHOR="${1:-/etc/pf.anchors/dalang.hardening}"
RULE="pass in quick proto udp from any port 68 to any port 67"
BLOCK_RE='^block drop in quick all'

[ -f "$ANCHOR" ] || { echo "anchor not found: $ANCHOR" >&2; exit 1; }

if grep -qF "$RULE" "$ANCHOR"; then
  echo "DHCP rule already present in $ANCHOR"
else
  cp "$ANCHOR" "$ANCHOR.bak.$(date +%s)"
  # insert the rule immediately before the final `block drop in quick all`
  perl -i -pe "print \"$RULE\n\" if /$BLOCK_RE/" "$ANCHOR"
  echo "inserted DHCP client→server rule into $ANCHOR"
fi

# reload the whole ruleset
pfctl -f /etc/pf.conf
echo "pf reloaded — VMs can now obtain DHCP leases"
