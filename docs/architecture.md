# Architecture

`mac-multi-server` turns one Apple Silicon Mac into a small VPS host. This doc explains how the
pieces fit and why each choice was made.

## Big picture

```
                                 INTERNET
                                    │   pf default-deny inbound · Cloudflare tunnel (outbound)
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  MAC STUDIO — BARE METAL host (macOS, Apple Silicon)                       │
│                                                                            │
│   ┌── CONTROL PLANE ─────────┐         ┌── MONITORING ──────────┐          │
│   │  dashboard + deploy API  │         │  Beszel hub            │          │
│   │  panel.$DOMAIN           │         │  monitor.$DOMAIN       │          │
│   └───────────┬──────────────┘         └────▲───▲───▲───────────┘          │
│               │ tart clone/set/run · cloudflare route · gen creds          │
│   cloudflared │ (routes vpsN.$DOMAIN → the VM)     │   │   │               │
│   Tart · VZ.framework · NAT bridge 192.168.64.0/24 │   │   │               │
│   ┌───────────▼──┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│   │  vps-1 (VM)  │  │ vps-2(VM)│  │ vps-3(VM)│  │ vps-N(VM)│               │
│   │  Ubuntu      │  │  Ubuntu  │  │  Ubuntu  │  │  Ubuntu  │               │
│   │  OpenClaw    │  │  blank   │  │ OpenClaw │  │   ...    │               │
│   │  +bz-agent ───┼──┼──────────┼──┼──────────┼──┘ metrics up               │
│   └──────────────┘  └──────────┘  └──────────┘                            │
│                                                                            │
│   (agent bundles use cloud/configured model APIs — no local GPU needed)    │
└──────────────────────────────────────────────────────────────────────────┘
```

## Components

| Layer | Tech | Role |
|---|---|---|
| Hypervisor | **Tart** (Apple Virtualization.framework) | runs each VPS as a real Linux VM on the metal |
| VPS | **Ubuntu 24.04** (aarch64) | the "droplet" — own OS/kernel/IP/SSH |
| Control plane | web dashboard + per-VPS detail page + web terminal | the 1-click UI; orchestrates Tart + Cloudflare |
| Ingress | **cloudflared** + Cloudflare DNS | domain SSH per VPS (`vpsN.$DOMAIN`) + `panel.`/`monitor.` — all outbound tunnel |
| Firewall | **pf** | default-deny inbound; DHCP allowed on the bridge (the platform opens no inbound port) |
| Monitoring | **Beszel** (hub + per-VPS agent) | live per-VPS CPU/RAM/disk/net, own login — **metrics/alerting** |
| Recovery | **health watchdog** (LaunchAgent) | probes each VPS, auto-restarts the unhealthy — **auto-recovery** |
| Config | **`.env`** | domain, tokens, defaults — nothing hardcoded |

## Why these choices (Apple Silicon realities)

1. **Linux guests, not macOS.** Apple caps macOS guests at **2 per host** (license + kernel-enforced, `VZErrorDomain` 6). Linux guests are **unlimited** (RAM/CPU-bound). VPS are Linux.
2. **Real VMs, not containers.** "Really VPS" → each gets its own kernel. Tart uses VZ.framework directly — most metal-direct, no parent-VM layer (Apple Silicon can't nest full VMs anyway).
3. **GPU not virtualized.** Metal isn't exposed to guests, so a *local* LLM can't run fast inside a VPS. The agent bundles (OpenClaw, Hermes Agent) don't need one — they call cloud/configured models. If you ever want local inference, it runs on the **host**, not in a guest.
4. **Cloudflare for ingress.** The Mac only needs :22 open; everything else reaches VPS through Cloudflare hostnames — no extra open ports, works behind NAT/changing IPs.

## Networking (summary — see networking.md)
- Tart puts VMs on a NAT bridge (`192.168.64.0/24`), DHCP served by macOS `bootpd`.
- **pf must allow the DHCP client→server direction** (`udp 68→67`) or VMs never get a lease. This is scripted in `./mms pf-fix` — the #1 gotcha.
- **Domain SSH, no IPs:** each deploy adds `vpsN.$DOMAIN → ssh://192.168.64.x:22` to the tunnel; tenants run `ssh admin@vpsN.$DOMAIN` after a one-time `~/.ssh/config` cloudflared snippet. No public or internal IP is exposed, and no jump host is used.

## Deploy flow (summary — see how-it-works.md)
`click → disk guard → tart clone → tart set specs → launchd run (persistent) → wait for IP → inject key → install bundle → beszel agent → cloudflare ssh route → record state`

## Persistence
- Each VPS runs under **launchd** so it survives reboot.
- The control plane and cloudflared are launchd services too.

## Failure & recovery
Two independent layers keep the fleet alive, and it's worth being precise about what each covers.

**1. launchd `KeepAlive` (per-VPS agent).** Every VPS runs as `tart run --no-graphics` under a
LaunchAgent with `KeepAlive`. launchd only watches the **host `tart` process**: if that process
dies (or the Mac reboots), launchd relaunches it. It has **no view inside the guest** — a guest
that OOMs, hangs, spins the CPU, or fills its disk keeps a live `tart` process, so KeepAlive does
**nothing** for it. That gap is what the watchdog closes.

**2. Health watchdog (`lib/watchdog.sh` + `io.macmultiserver.watchdog` LaunchAgent).** Installed by
`install.sh`, it runs `./mms watchdog` every `WATCHDOG_INTERVAL` seconds (default **60s**). Each
pass, for every VPS whose desired state isn't `stopped`:
- **Probe** = `tart ip <name>` resolves **and** `ssh admin@<ip> true` succeeds (key-based, short
  timeouts). Healthy → status `running`, fail counter reset.
- **Unhealthy** → increment the counter; after `WATCHDOG_FAIL_THRESHOLD` **consecutive** fails
  (default **3**, so a blip won't trigger anything) it runs `vps_restart` (`tart stop` +
  `launchctl kickstart -k`), writing status `unhealthy` → `restarting` → back to `running`.
- **Back-off (anti-flap):** at most `WATCHDOG_MAX_RESTARTS` (default **3**) restarts inside
  `WATCHDOG_BACKOFF_WINDOW` (default **900s**). Exceed that and the VPS is marked `flapping` and
  left alone — no restart loop. The counter resets once the window elapses.
- A **deliberately Stopped** VPS (status `stopped`) is skipped entirely — never probed or restarted.

Status lands in `state/<name>.json`, so the dashboard reflects real health; the log is
`/tmp/io.macmultiserver.watchdog.log`. This is **auto-recovery** — distinct from Beszel, which is
**metrics/alerting** (see [monitoring.md](monitoring.md)).

**Resource isolation (what one bad VPS can and can't do to others).**
- **RAM** is **hard-capped** per VM (`tart set --memory`); a guest can't exceed its allocation.
- **Disk** is **capped to each VM's own image** (`tart set --disk-size`); a guest can't grow past it.
- **CPU** is **shared** — vCPU count is set per VM, but there's no hard per-VM CPU quota, so a
  spinning guest competes for host cores. (The watchdog still recovers a VM it wedges.)
- **Host free-disk guard:** many sparse VM clones can still exhaust the *Mac's* disk, which
  endangers **all** VPS. So `vps_deploy` refuses a deploy that would drop host free space below a
  floor: `need = max(VPS_MIN_FREE_GB, disk-size + VPS_DISK_MARGIN_GB)` (defaults **20 GB** floor,
  **10 GB** margin). Free space or lower `--disk` to proceed.

## Reset story
Everything is in the repo + `.env`. To rebuild from scratch:
```
wipe VMs → git pull → restore .env → ./install.sh
```
