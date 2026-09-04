# Networking

How traffic flows, and the gotchas that will otherwise cost you an afternoon.

## The layers
```
INTERNET ──► Cloudflare ──► cloudflared (on Mac) ──► VPS (192.168.64.x)
                                                     ▲
you ──ssh──► Mac (:22) ──ProxyJump──► VPS (:22) ─────┘   (admin path)
```

- **Tart NAT bridge:** every VM lands on `192.168.64.0/24` (bridge100). Gateway `192.168.64.1`.
- **DHCP:** served by macOS `bootpd` (Internet Sharing subsystem). `tart ip <vm>` reads the lease.
- **Ingress:** cloudflared maps `vpsN.$DOMAIN` → `192.168.64.x:<port>`; DNS is a CNAME to the tunnel.

## Gotcha #1 — pf blocks VM DHCP (the big one)
A hardened Mac with default-deny pf (`block drop in quick all`) will **silently drop the VM's
DHCP request**. The DISCOVER is `0.0.0.0:68 → 255.255.255.255:67` — no source IP yet — so it
matches neither the `192.168.64.0/24` pass rule nor the common `67→68` server-direction rule.
The VM boots to a login prompt but **never gets an IP** (and shows 0% CPU — idle, not stuck).

**Fix:** allow the client→server direction. `./mms pf-fix` adds, before the block:
```
pass in quick proto udp from any port 67 to any port 68   # server → client (already there)
pass in quick proto udp from any port 68 to any port 67   # client → server (THIS is the fix)
```
Diagnose it: `sudo dhcpd_leases` shows no new lease, and the VM's MAC never appears in `arp -an`.

## Gotcha #2 — DHCP lease exhaustion with many VMs
Default macOS DHCP lease is 24h. Running many short-lived VMs can exhaust the pool. Shorten it:
```
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist \
  bootpd -dict DHCPLeaseTimeSecs -int 600
```

## Gotcha #3 — DHCP IPs change across reboots
`tart ip` is a DHCP address and can change. For stable per-VPS routing we either (a) pin a
static IP inside each guest on `192.168.64.0/24`, or (b) resolve the IP at deploy time and
(re)write the cloudflared ingress + SSH config. `mac-multi-server` does (b) on deploy, and can pin
(a) for long-lived VPS.

## Firewall posture (unchanged for the internet)
Only **:22** is open to the internet; pf drops everything else inbound. VPS are **not** directly
reachable from outside — they're reached through Cloudflare (HTTP apps) or SSH ProxyJump (admin).
The DHCP rule only affects the internal `192.168.64.0/24` bridge, not the public interface.

## Reaching a VPS
- **HTTP app:** `https://vpsN.$DOMAIN` → cloudflared → VPS port.
- **SSH (admin):** `ssh -J <mac> admin@192.168.64.x`, or a `Host vpsN` block with `ProxyJump`.
- **Tenant handover:** give them only `vpsN.$DOMAIN` + their key — they never touch the host.
