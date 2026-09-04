# How it works — the deploy flow

What happens between clicking **Deploy** and getting a live VPS.

## Deploy
```
click "Deploy"  (specs + bundle)         e.g. cpu=2 mem=4096 disk=40 bundle=openclaw
        │
        ▼
1. tart clone  $TEMPLATE  vps-{n}          # template = base image with the bundle baked in
2. tart set    vps-{n} --cpu 2 --memory 4096 --disk 40
3. launchd     load io.vantis.vps-{n}       # `tart run --no-graphics` — persistent
4. wait for IP  (tart ip vps-{n})           # pf already allows DHCP (./mms pf-fix)
5. inject key   (first login, then key-only)
6. cloudflare   route  vps{n}.$DOMAIN → 192.168.64.x:<app-port>
                       + DNS CNAME → tunnel
7. record       state/vps-{n}.json  (specs, ip, hostname, created, bundle)
        │
        ▼
show the DETAILS card:
   name · status · Ubuntu 24.04 · 2 vCPU / 4 GB / 40 GB
   Host:  vps{n}.$DOMAIN
   App:   https://vps{n}.$DOMAIN        (if bundle exposes one)
   SSH:   ssh admin@vps{n}.$DOMAIN
   live CPU/RAM (Netdata)
```

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

## Persistence & reset
- Each VPS + the control plane + cloudflared are **launchd** services → survive reboot.
- Full reset: wipe VMs → `git pull` → restore `.env` → `./install.sh`.

## State
Per-VPS metadata lives in `state/*.json` (gitignored). The dashboard reads it to render cards;
`destroy` removes it. Nothing about a VPS is hidden in someone's head — it's all in state + `.env`.
