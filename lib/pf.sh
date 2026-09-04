#!/usr/bin/env bash
# pf.sh — ensure the pf firewall lets Tart VMs get a DHCP lease.
#
# THE #1 GOTCHA: a default-deny pf ruleset (`block drop in quick all`) drops a VM's
# DHCP DISCOVER (0.0.0.0:68 → 255.255.255.255:67 matches no pass rule). VMs boot but
# never get an IP. Fix: allow the client→server direction before the block. Idempotent.
# Needs sudo. See docs/networking.md.

pf_allow_dhcp() {
  local anchor="${1:-/etc/pf.anchors/dalang.hardening}"
  local rule="pass in quick proto udp from any port 68 to any port 67"
  [ -f "$anchor" ] || { warn "no pf anchor at $anchor — skipping (see docs/networking.md)"; return 0; }
  if grep -qF "$rule" "$anchor"; then
    ok "pf already allows VM DHCP"
  else
    cp "$anchor" "$anchor.bak.$(date +%s)"
    perl -i -pe "print \"$rule\n\" if /^block drop in quick all/" "$anchor"
    ok "added DHCP client→server rule to $anchor"
  fi
  pfctl -f /etc/pf.conf 2>/dev/null && ok "pf reloaded"
}
