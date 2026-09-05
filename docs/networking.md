# Networking

How traffic flows, and the gotchas that will otherwise cost you an afternoon.

## The layers
```
SSH:        tenant ──cloudflared access ssh──► Cloudflare ──► cloudflared (on Mac) ──► VPS 192.168.64.x:22
infra HTTP: INTERNET ──► Cloudflare ──► cloudflared (on Mac) ──► panel/monitor on 127.0.0.1
```

The tunnel is **outbound** from the Mac: cloudflared dials Cloudflare, so nothing inbound
has to be opened to reach a VPS or the panel.

- **Tart NAT bridge:** every VM lands on `192.168.64.0/24` (bridge100). Gateway `192.168.64.1`.
- **DHCP:** served by macOS `bootpd` (Internet Sharing subsystem). `tart ip <vm>` reads the lease.
- **Ingress:** cloudflared maps a hostname to a local service (an ingress rule on the tunnel
  config + a proxied DNS CNAME):
  - **per VPS, at deploy:** `vpsN.$DOMAIN → ssh://192.168.64.x:22` (`cf_ssh_route_add`), so the
    hostname is the VPS's **SSH** endpoint. The internal IP is recorded in state but never routed
    publicly for HTTP — a per-VPS app hostname is not wired automatically today (the `app_port` is
    recorded, and `cf_route_add` exists for HTTP, but nothing calls it per VPS yet).
  - **infra, at install:** `panel.$DOMAIN → http://127.0.0.1:<panel-port>` and
    `monitor.$DOMAIN → http://127.0.0.1:8090` (`cf_route_add`).

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
`tart ip` is a DHCP address and can change. `mac-multi-server` resolves the IP at deploy time and
writes the cloudflared ingress (and the IP into `state/<name>.json`). A per-VPS `ssh://ip:22`
ingress rule is (re)written each deploy so `vpsN.$DOMAIN` always points at the current lease.

## Firewall posture
pf runs default-deny inbound; the platform itself opens **no** inbound port — cloudflared reaches
Cloudflare outbound, and VPS live only on the internal `192.168.64.0/24` bridge, never directly
reachable from outside. The DHCP rule `pf-fix` adds only affects that internal bridge, not the
public interface. (If you also administer the Mac host directly you'd keep :22 open for that, but
tenants and the panel never need it — everything they touch rides the tunnel.)

## Reaching a VPS — domain SSH (no IPs)
Each VPS is reached over SSH **by hostname**, through the Cloudflare tunnel — no public or internal
IP is ever handed to a tenant, and no jump host is involved.

**One-time, on the tenant's machine:** install
[`cloudflared`](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/),
then add to `~/.ssh/config`:
```
Host *.$DOMAIN
  ProxyCommand cloudflared access ssh --hostname %h
```
**Then, forever after:**
```
ssh admin@vpsN.$DOMAIN
```
`cloudflared access ssh` opens a connection to the Cloudflare edge; the tunnel routes it to
`ssh://192.168.64.x:22` inside the bridge. **Tenant handover:** give them only `vpsN.$DOMAIN`, the
one-line `~/.ssh/config` snippet, and their key — they never see an IP or touch the host. The
control-plane detail page (`/vps/:name`) shows the exact `ssh` command and this snippet with a
copy button, plus a browser-based web terminal (see [control-plane.md](control-plane.md)).
