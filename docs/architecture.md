# Architecture

`mac-multi-server` turns one Apple Silicon Mac into a small VPS host. This doc explains how the
pieces fit and why each choice was made.

## Big picture

```
                                 INTERNET
                                    │   only :22 open · pf firewall · Cloudflare
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  MAC STUDIO — BARE METAL host (macOS, Apple Silicon)                       │
│                                                                            │
│   ┌── CONTROL PLANE ─────────┐         ┌── MONITORING ──────────┐          │
│   │  dashboard + deploy API  │         │  Netdata / Grafana     │          │
│   │  panel.$DOMAIN           │         │  grafana.$DOMAIN       │          │
│   └───────────┬──────────────┘         └────▲───▲───▲───────────┘          │
│               │ tart clone/set/run · cloudflare route · gen creds          │
│   cloudflared │ (routes vpsN.$DOMAIN → the VM)     │   │   │               │
│   Tart · VZ.framework · NAT bridge 192.168.64.0/24 │   │   │               │
│   ┌───────────▼──┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│   │  vps-1 (VM)  │  │ vps-2(VM)│  │ vps-3(VM)│  │ vps-N(VM)│               │
│   │  Ubuntu      │  │  Ubuntu  │  │  Ubuntu  │  │  Ubuntu  │               │
│   │  OpenClaw    │  │  blank   │  │ OpenClaw │  │   ...    │               │
│   │  +netdata ───┼──┼──────────┼──┼──────────┼──┘ metrics up               │
│   └──────────────┘  └──────────┘  └──────────┘                            │
│                                                                            │
│   (LLM brain on host — LATER; VPS will call it over the bridge)            │
└──────────────────────────────────────────────────────────────────────────┘
```

## Components

| Layer | Tech | Role |
|---|---|---|
| Hypervisor | **Tart** (Apple Virtualization.framework) | runs each VPS as a real Linux VM on the metal |
| VPS | **Ubuntu 24.04** (aarch64) | the "droplet" — own OS/kernel/IP/SSH |
| Control plane | web dashboard + deploy API | the 1-click UI; orchestrates Tart + Cloudflare |
| Ingress | **cloudflared** + Cloudflare DNS | gives each VPS a public hostname on your domain |
| Firewall | **pf** | only SSH open to the internet; DHCP allowed on the bridge |
| Monitoring | **Netdata** (→ Grafana later) | live per-VPS CPU/RAM/net |
| Config | **`.env`** | domain, tokens, defaults — nothing hardcoded |

## Why these choices (Apple Silicon realities)

1. **Linux guests, not macOS.** Apple caps macOS guests at **2 per host** (license + kernel-enforced, `VZErrorDomain` 6). Linux guests are **unlimited** (RAM/CPU-bound). VPS are Linux.
2. **Real VMs, not containers.** "Really VPS" → each gets its own kernel. Tart uses VZ.framework directly — most metal-direct, no parent-VM layer (Apple Silicon can't nest full VMs anyway).
3. **GPU not virtualized.** Metal isn't exposed to guests, so LLM inference can't run fast inside a VPS. When Hermes/LLM lands, the model runs on the **host** and VPS call it over the bridge. Hence "no LLM first."
4. **Cloudflare for ingress.** The Mac only needs :22 open; everything else reaches VPS through Cloudflare hostnames — no extra open ports, works behind NAT/changing IPs.

## Networking (summary — see networking.md)
- Tart puts VMs on a NAT bridge (`192.168.64.0/24`), DHCP served by macOS `bootpd`.
- **pf must allow the DHCP client→server direction** (`udp 68→67`) or VMs never get a lease. This is scripted in `scripts/pf-allow-dhcp.sh` — the #1 gotcha.
- cloudflared maps `vpsN.$DOMAIN` → `192.168.64.x:<port>` (ingress rules generated per deploy).

## Deploy flow (summary — see how-it-works.md)
`click → tart clone template → tart set specs → launchd run (persistent) → wait for IP → cloudflare route → generate creds → show details card`

## Persistence
- Each VPS runs under **launchd** so it survives reboot.
- The control plane and cloudflared are launchd services too.

## Reset story
Everything is in the repo + `.env`. To rebuild from scratch:
```
wipe VMs → git pull → restore .env → ./scripts/setup-host.sh
```
