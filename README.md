# Mac-multi-server

**One Mac. Click. A real VPS.**

A self-hosted, 1-click VPS platform that runs on a single Apple Silicon Mac (bare metal).
Pick specs + an app bundle (e.g. OpenClaw), hit **Deploy**, and in ~30s you get a real
Linux VPS — its own OS, kernel, SSH, and resource quotas — reachable **by domain** through
Cloudflare, with no IP ever exposed. Like a DigitalOcean droplet, but on your own metal.

```
panel.yourdomain.com  →  [ Deploy ]  →  ssh admin@vps7.yourdomain.com   (Ubuntu + OpenClaw, live in ~30s)
```

## Why
Apple Silicon Macs are cheap, fast, low-power compute. This turns one into a small VPS
host: real Linux VMs (via Tart on Apple's Virtualization.framework), a web control plane
to deploy/monitor them, and Cloudflare to give each one a public hostname — no cloud bill.

## What you get
- **Real VPS** — each is a genuine Linux VM (own kernel), not a shared container.
- **1-click deploy** — choose CPU / RAM / disk + a bundle, click, done.
- **App bundles** — deploy blank, or pre-loaded with an agent: **OpenClaw** or **Hermes Agent**.
- **Domain SSH, no IPs** — reach a VPS with `ssh admin@vpsN.yourdomain.com` through the Cloudflare
  tunnel (one-time `~/.ssh/config` cloudflared snippet). No public or internal IP, no jump host.
- **Manage from the panel** — a per-VPS detail page with specs, copy-paste SSH, **rename** (a Name
  tag; the id stays `vps-N`), **Restart / Stop / Start / Terminate**, and a **web terminal** (xterm.js
  in the browser, straight to the VM).
- **Self-healing** — a health watchdog probes each VPS and auto-restarts the unhealthy, with a
  back-off so a genuinely broken VM is flagged "flapping" instead of restarted forever.
- **Monitoring** — live CPU/RAM/disk/net per VPS via **Beszel** (self-hosted hub + a tiny agent per VPS).
- **Reproducible** — all config in `.env`; reset = wipe VMs, `git pull`, restore `.env`, run one script.

## Hard truths (Apple Silicon)
- **Linux guests only for the VPS.** macOS guests are capped at 2 per host by Apple; Linux is unlimited (RAM/CPU-bound).
- **No GPU in guests.** Metal isn't virtualized, so a *local* LLM can't run fast inside a VPS. The agent bundles (OpenClaw, Hermes Agent) don't need one — they use cloud/configured models. Local inference, if ever wanted, would run on the host.

## Quickstart
> ⚠️ **Clone to your home dir, NOT `~/Desktop`/`~/Documents`/`~/Downloads`.** Those are
> TCC-protected on macOS, and launchd services can't run binaries from there (they hang in
> dyld). `install.sh` will refuse a TCC path and tell you to move it.

```bash
git clone <this repo> ~/mac-multi-server && cd ~/mac-multi-server
cp .env.example .env          # fill in DOMAIN + Cloudflare token (see docs/setup.md)
./install.sh       # install Tart, fix pf for DHCP, build+run the panel, watchdog, monitoring, wire cloudflared
./mms deploy --bundle openclaw --cpu 2 --mem 4096 --disk 40
# → prints the VPS details: status, specs, SSH-by-domain, and the panel manage/terminal URL
```

## Docs
- [docs/architecture.md](docs/architecture.md) — how the whole thing fits together
- [docs/setup.md](docs/setup.md) — host prep, Cloudflare token, `.env`
- [docs/cloudflare.md](docs/cloudflare.md) — **beginner** click-by-click for the Cloudflare values
- [docs/control-plane.md](docs/control-plane.md) — the web panel: design, routes, security, UI workflow
- [docs/how-it-works.md](docs/how-it-works.md) — the deploy flow, step by step
- [docs/networking.md](docs/networking.md) — pf/DHCP, the bridge, Cloudflare routing
- [docs/monitoring.md](docs/monitoring.md) — Beszel hub + per-VPS agents, first-time setup

## Layout
```
install.sh       one-shot host setup (clone → ./install.sh)
uninstall.sh     clean teardown (--purge for images too) — wipes clean like docker/nix
mms              the CLI: deploy · destroy · restart · stop · start · watchdog · ls · logs · pf-fix
lib/             sourced helpers: common · pf · cloudflare · vps · watchdog
templates/       VPS bundles: blank/, openclaw/, hermes/
control-plane/   native Swift panel (login + dashboard + per-VPS detail page + web terminal) → macserver-panel
flake.nix        `nix develop` for the CLI tooling (cloudflared, sshpass, jq)
docs/            architecture & guides
.env.example     config template (copy to .env)
```
Both the CLI (`./mms`) and the web panel call the **same** engine in `lib/` — one source of truth.

## Uninstall (clean, like docker/nix)
```bash
./uninstall.sh            # remove all VPS, the panel, monitoring routes, state + services
./uninstall.sh --purge    # also remove cached base images + the DNS helper
```
Everything the platform created is removed; your `.env` and the repo folder stay until you delete them.

## Status
Working end-to-end. One-command install; 1-click deploy of real Linux VMs on the metal;
domain-only SSH (no IP exposed) + in-browser web terminal; a web panel with per-VPS detail,
rename, and restart/stop/start; a health watchdog that auto-restarts unhealthy VMs (with
back-off); Beszel monitoring; a host free-disk guard; and clean install/uninstall. Actively
evolving — see [docs/](docs/).
