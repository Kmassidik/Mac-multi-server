# Monitoring (Beszel)

Monitoring is [**Beszel**](https://beszel.dev) — a tiny, self-hosted, multi-server monitor.
A **hub** (dashboard) runs on the Mac; a small **agent** runs in each VPS and reports CPU / RAM
/ disk / network back to the hub. It has its **own login**, so it's not exposed openly.

> **Beszel vs the watchdog — distinct roles.** Beszel is **metrics/alerting**: it shows and alerts
> on resource usage, but it doesn't act on a VPS. Auto-**recovery** (probe + restart unhealthy VMs)
> is the separate health watchdog — see
> [architecture.md → Failure & recovery](architecture.md#failure--recovery).

## How it fits
```
each VPS:  beszel-agent ──(outgoing WebSocket)──► hub at http://192.168.64.1:8090  (the Mac, on the VM bridge)
you:       https://monitor.$DOMAIN ──cloudflared──► hub 127.0.0.1:8090  (Beszel's own login)
```
- The **hub** is a single binary (~30 MB) in `~/.beszel`, run as a LaunchDaemon on `0.0.0.0:8090`.
  It's bound to all interfaces so VPS agents can reach it on the bridge (`192.168.64.1:8090`),
  but pf still blocks `:8090` from the internet — only `:22` is open. History lives in
  `~/.beszel/pb_data` (small; low-resolution — typically well under 100 MB).
- The **agent** connects *out* to the hub (WebSocket), so no inbound port is opened on the VPS.

## First-time setup (2 minutes, once)
`install.sh` installs and starts the hub automatically, and **creates the hub admin from `.env`**
so you skip Beszel's first-run web form:

```
BESZEL_ADMIN_EMAIL=you@example.com
BESZEL_ADMIN_PASSWORD=change-me-8+chars   # must be ≥8 chars
```

Log in at **`https://monitor.$DOMAIN`** with those, then wire up auto-reporting agents:

1. Go to **Settings → Tokens** and copy a **universal token**.
2. In the same area, copy the agent **public key** (shown in "Add System").
3. Put both in `.env`:
   ```
   BESZEL_KEY=<the public key>
   BESZEL_TOKEN=<the universal token>
   BESZEL_HUB_URL=http://192.168.64.1:8090   # default; the Mac on the VM bridge
   ```

That's it. **Every VPS you deploy after this auto-installs the agent** and shows up in the hub —
no per-server clicking. (VPS deployed before you set the token won't have the agent; redeploy
or add it by hand from the hub's "Add System" dialog.)

## Alerts
Per system, open it in the hub and add alert rules (Beszel stores them in its `alerts`
collection). Sensible defaults for a VPS:

| Alert    | Threshold        | Catches |
|----------|------------------|---------|
| Status   | down ≥ 2 min     | agent offline / VM unreachable (complements the watchdog) |
| CPU      | > 90% for 5 min  | runaway / pegged CPU |
| Memory   | > 90% for 5 min  | memory pressure before OOM |
| Disk     | > 90%            | guest filling its own disk |

By default alerts are shown **in the dashboard**. To be notified elsewhere, configure a
notification channel in Beszel (SMTP for email, or a shoutrrr/webhook URL for Slack/Discord/etc.)
under the user's settings — without one, alerts trigger but don't send.

> Alerts (notify) are distinct from the health **watchdog** (auto-restart) — see
> [architecture.md → Failure & recovery](architecture.md#failure--recovery). The **Status** alert
> and the watchdog overlap usefully: the watchdog tries to *fix* an unreachable VPS, the alert
> *tells you* it happened.

## Why Beszel (vs Netdata)
- **Self-hosted + own login** — Netdata's agent dashboard is cloud-first and pushes you to
  `app.netdata.cloud`; Beszel stays entirely on your metal, behind its own auth.
- **Tiny** — ~30 MB hub + ~15 MB agents, low-res history. Netdata/Prometheus store far more.
- **Multi-server by design** — one hub, an agent per VPS, exactly matching this platform.

## Uninstall
`./uninstall.sh` stops and removes the hub service + the `monitor.$DOMAIN` route.
`./uninstall.sh --purge` also deletes `~/.beszel` (hub binary + history + admin).
