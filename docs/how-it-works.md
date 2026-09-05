# How it works — the deploy flow

What happens between clicking **Deploy** and getting a live VPS.

## Deploy
```
click "Deploy"  (specs + bundle)         e.g. cpu=2 mem=4096 disk=40 bundle=openclaw
        │
        ▼
0. disk guard   refuse if the Mac would drop below the free-disk floor (VPS_MIN_FREE_GB /
                VPS_DISK_MARGIN_GB) — see "Failure & recovery" in architecture.md
1. tart clone  $VPS_BASE_IMAGE  vps-{n}     # base image (bundle installed after boot, below)
2. tart set    vps-{n} --cpu 2 --memory 4096 --disk-size 40
3. launchd     io.macmultiserver.vps-{n}    # `tart run --no-graphics` — persistent, KeepAlive
4. wait for IP  (tart ip vps-{n})           # pf must allow DHCP (./mms pf-fix)
5. inject key   (first login over sshpass, then key-only)
6. install      run the bundle's install.sh inside the guest (blank = skip)
7. monitoring   install the Beszel agent (if BESZEL_KEY/TOKEN set) — reports out to the hub
8. cloudflare   ssh route  vps{n}.$DOMAIN → ssh://192.168.64.x:22   (cf_ssh_route_add)
                           + proxied DNS CNAME → tunnel
9. record       state/vps-{n}.json  (name, label, bundle, status, specs, ip, app_port,
                                      ssh_host, created)
        │
        ▼
prints the details:
   ✓ vps-{n}  ● running · Ubuntu · 2vCPU/4096MB/40GB · openclaw
   IP (host-side): 192.168.64.x
   SSH: ssh admin@vps{n}.$DOMAIN   (tenant adds a one-line ~/.ssh/config cloudflared snippet)
   Manage/terminal: https://panel.$DOMAIN/vps/vps-{n}
   Destroy: ./mms destroy vps-{n}
```
The panel's per-VPS detail page (`/vps/vps-{n}`) shows the SSH command, the `~/.ssh/config`
snippet, a web terminal, rename, and Restart/Stop/Start — see [control-plane.md](control-plane.md).
`vps{n}.$DOMAIN` is the **SSH** endpoint; a per-VPS public HTTP app URL is not wired automatically
today (see [networking.md](networking.md)).

## Bundles
A bundle is a folder in `templates/` with an `install.sh` that runs inside the guest on
deploy. Its install URL comes from `.env` (easy to change if a vendor link moves):
- **blank** — plain Ubuntu 24.04, nothing installed.
- **openclaw** — [OpenClaw](https://openclaw.ai): open-source personal AI assistant. Uses cloud/configured models. Finish setup over SSH: `openclaw onboard`.
- **hermes** — [Hermes Agent](https://hermes-agent.nousresearch.com) (Nous Research): open-source multi-channel agent (Telegram/Discord/… + persistent memory). Uses cloud/configured models.

Both agents run entirely inside the VPS and need no local GPU. To add your own bundle, drop a
`templates/<name>/install.sh` and add `<name>` to `BUNDLES` in `.env`.

## Destroy (clean, no residue)
```
./mms destroy vps-{n}
  → launchd unload + tart stop
  → tart delete vps-{n}
  → cloudflare: remove route + DNS record
  → rm state/vps-{n}.json
```

## Lifecycle (restart / stop / start)
Beyond deploy/destroy, each VPS can be managed from `./mms` or the detail page:
- **restart** — `tart stop` then `launchctl kickstart -k` the VM's LaunchAgent (KeepAlive stays on).
- **stop** — `launchctl bootout` the agent (so KeepAlive won't relaunch) + `tart stop`; the plist is
  kept. Status becomes `stopped`, and the watchdog skips it (a deliberate stop is respected).
- **start** — re-bootstrap the kept plist. Status back to `running`.

## Persistence, health & reset
- Each VPS + the control plane + cloudflared are **launchd** services → survive reboot.
- A **health watchdog** LaunchAgent probes every running VPS and auto-restarts unhealthy ones with
  a back-off. What each layer does — and doesn't — recover is in
  [architecture.md → Failure & recovery](architecture.md#failure--recovery).
- Full reset: wipe VMs → `git pull` → restore `.env` → `./install.sh`.

## State
Per-VPS metadata lives in `state/*.json` (gitignored). The dashboard reads it to render cards;
`destroy` removes it. Nothing about a VPS is hidden in someone's head — it's all in state + `.env`.
