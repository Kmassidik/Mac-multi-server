# Control plane (the web panel)

The panel is a **native Swift binary** (`macserver-panel`) that renders the UI **server-side**
and drives the same `./mms` engine the CLI uses. It's login-gated, binds `127.0.0.1`, and is
reached only through Cloudflare (`panel.$DOMAIN`). It presents an **AWS/GCP-style console** — a
resource table (or card) view of instances, and a tabbed per-VPS detail page.

## Rendering model — SSR pages + a thin live layer
Pages are rendered **server-side** (login, dashboard, per-VPS detail): it keeps the attack
surface small for a panel that can create/destroy servers — mutations are CSRF-protected form
POSTs, with output escaping in one place. On top of that, a small amount of client JS
(`web/app.js`) adds a live layer: a few **read-only JSON endpoints** (`/api/vps`,
`/vps/:name/status`, `/vps/:name/metrics`) that the pages poll to update status, controls, and
metrics **in place**, and AJAX submission of the lifecycle POSTs so an action doesn't reload the
page. The UI still lives in real files (below), so design is easy to work on.

Static assets (`/style.css`, `/app.js`) are **cache-busted** with a `?v=<version>` query
(`ASSET_VER`, a timestamp set at each process start), so a rebuilt/restarted panel serves fresh
CSS/JS through the browser and Cloudflare without a manual cache purge.

## Layout
```
web/                       ← the UI (edit here; no recompile to restyle)
  style.css                shared styles (light + spring-green console theme)
  app.js                   client JS: deploy-form size presets + live summary, password eye,
                           live status polling, AJAX lifecycle actions, styled confirm dialog,
                           card/table view toggle, in-tab live metrics
  setup.html               first-run: create admin
  login.html               sign in
  dashboard.html           deploy form (bundle tiles) + resource console (table / cards)
  vps.html                 per-VPS detail page: tabs — Overview / Monitoring / Access / Danger
  vendor/                  self-hosted xterm.js (+ fit addon) for the web terminal
control-plane/Sources/Panel/
  main.swift               args + start server
  Routes.swift             routes, sessions, auth checks, CSRF, rate-limit, terminal WebSocket
  Pages.swift              tiny renderer: load web/<tpl>, substitute {{TOKENS}}, inject fragments
  Store.swift              read state/*.json, list bundles (templates/*/meta.json), call ./mms
  PTY.swift                PTYBridge: spawns ssh in a real pty, pipes bytes ⇄ the terminal socket
  Auth.swift               PBKDF2-HMAC-SHA256 admin credential
  Config.swift             read .env
control-plane/Sources/CPTY/   small C shim: openpty + window-size ioctls for PTY.swift
```
Templates use `{{TOKEN}}` placeholders; `Pages.swift` fills them and injects the data-driven
bits (bundle cards, server cards, error/notice blocks). Swift serves `/style.css` and `/app.js`
as static files.

## Routes
| Method · path | Purpose |
|---|---|
| `GET /` | authed → 302 `/dashboard`; else serve login (or setup on first run) + a CSRF cookie |
| `GET /dashboard` | the console (resource table / cards + deploy form); **302 to `/` if not signed in** |
| `GET /vps/:name` | per-VPS **detail page** (tabbed: Overview / Monitoring / Access / Danger); 302 if not signed in / no such VPS |
| `GET /api/vps` | **JSON** `[{name,status}, …]` — polled by the dashboard (every 4s) to update tags + the running count in place |
| `GET /vps/:name/status` | **JSON** `{status}` — polled by the detail page (every 3s) to update the tag + controls in place |
| `GET /vps/:name/metrics` | **JSON** live metrics for the Monitoring tab — panel proxies the Beszel hub (see [monitoring.md](monitoring.md)) |
| `GET /style.css`, `GET /app.js` | static assets from `web/` (referenced with `?v=<version>` for cache-busting) |
| `GET /logos/:file`, `GET /vendor/:file` | bundle logos + vendored xterm.js (basename-only, whitelisted extensions) |
| `POST /setup` | first-run: create admin (CSRF-checked), then session + 302 `/dashboard` |
| `POST /login` | verify (CSRF-checked, rate-limited), session + 302 `/dashboard` |
| `POST /logout` | drop session, clear cookie, 302 `/` |
| `POST /deploy` | authed + CSRF → `./mms deploy …` (background), 302 `/dashboard` (new VPS shows as a live `provisioning` flag) |
| `POST /destroy` | authed + CSRF → `./mms destroy <name>`, 302 `/dashboard` (submitted via AJAX; row/card removed live) |
| `POST /vps/:name/rename` | authed + CSRF → set the human **Name tag** (id stays `vps-N`), 302 back |
| `POST /vps/:name/restart` | authed + CSRF → `./mms restart <name>`, 302 back (submitted via AJAX) |
| `POST /vps/:name/stop` | authed + CSRF → `./mms stop <name>`, 302 back (submitted via AJAX) |
| `POST /vps/:name/start` | authed + CSRF → `./mms start <name>`, 302 back (submitted via AJAX) |
| `GET /vps/:name/term` | **WebSocket** web terminal — authed + Origin-checked; one ssh pty per connection |

(`monitor.$DOMAIN` is **not** a panel route — cloudflared sends it straight to the Beszel hub, which has its own login. See [monitoring.md](monitoring.md).)

## Dashboard — the resource console (`/dashboard`)
An AWS/GCP-style console rendered from `web/dashboard.html`:
- **Resource views** — a **table** (default) and a **cards** view of every instance, toggled with
  a segmented control. The choice is remembered per browser in `localStorage` (`mms_view`).
- **Table columns** — Name · ID (`vps-N`) · Status · Bundle · Type (`Nc · N GB · N G`) · IP ·
  Created · row actions (Manage ↗, Terminate).
- **Breadcrumb** — `Home › Instances`.
- **Running count** — an accurate `R/N running` badge (running instances over total), kept current
  by the live poller.
- **Deploy form** — shown inline when there are no servers, or via the **+ New server** button
  (see "Deploy form" below).

## Deploy form
Header **"pick an image"**. It's a real form (`POST /deploy`), enhanced by `app.js`:
- **Bundle tiles** — one per bundle from `BUNDLES`, each showing `🐧 Ubuntu 24.04 LTS · + <agent>`
  (the base OS, plus the agent for non-blank bundles). Selection is pure CSS (a checked radio).
- **Size** — `S` / `M` / `L` presets plus **Custom** (vCPU, RAM in **GB**, Disk in **GB**). The
  RAM value is converted **GB → MB** on submit (the engine takes `--mem` in MB); vCPU/disk pass
  through. Defaults are the `M` preset so it works even without JS.
- **Name** — an optional Name tag (≤60 chars).
- **Live summary** — a one-line preview, e.g. `OpenClaw on Ubuntu · 2 vCPU · 4 GB · 40 GB`.

On submit the panel kicks off `./mms deploy …` in the background and returns to the dashboard,
where the new instance appears immediately as a live **`provisioning`** flag (pulsing amber) and
streams to `running` on its own — no manual refresh.

## VPS detail page (`/vps/:name`)
An AWS-style instance page rendered from `web/vps.html`, organised into **tabs** (with a header
that carries the instance name + live status tag, the web-terminal button, and a Metrics link):
- **Overview** — **Specifications** (Image = bundle base OS e.g. Ubuntu 24.04 LTS, Bundle, Compute
  in vCPU, Memory in **GB**, Storage in GB, SSH domain, host-only IP, Created) and **Power**
  (lifecycle controls + Name-tag rename).
- **Monitoring** — this VPS's live CPU / Memory / Disk as bars, proxied from the Beszel hub, plus
  a "Full graphs in Beszel" link. See [monitoring.md](monitoring.md).
- **Access** — SSH by domain: the `ssh admin@vpsN.$DOMAIN` command with a copy button, plus the
  one-time `~/.ssh/config` cloudflared snippet (`Host *.$DOMAIN` / `ProxyCommand cloudflared access
  ssh --hostname %h`). No IP is shown to a tenant. (If Cloudflare keys aren't set, it falls back to
  the raw IP for local use.) See [networking.md](networking.md).
- **Danger** — Terminate (destroys the VM + its disk), behind a styled confirmation.

Details:
- **Name tag** — rename the server (AWS-style, ≤60 chars). The **id** stays `vps-N`; the label is
  what the console and page title show.
- **Controls** — Restart (when not stopped), Stop (when running) / Start (when stopped), Terminate.
  These call the same `./mms` lifecycle the CLI uses, submitted via AJAX with a loading label; the
  visible set updates in place as status changes.
- **Web terminal** — a button (enabled only once the VPS is `running`) opens a modal terminal (below).

## Web terminal
A browser terminal to a VPS, with no exposed port and nothing to install client-side:
- The page loads **self-hosted xterm.js** (`web/vendor/`, served from `/vendor/:file`).
- Opening the modal opens a WebSocket to `GET /vps/:name/term`. `PTYBridge` (`PTY.swift`, backed by
  the tiny `CPTY` C shim for `openpty`/window-size ioctls) spawns `/usr/bin/ssh -tt -i
  ~/.ssh/id_ed25519 admin@<ip>` in a real pty and pipes bytes both ways — keystrokes as binary
  frames, `{"resize":[cols,rows]}` as a text control message. The panel runs on the Mac, so it
  reaches the VPS **directly over the Tart bridge** with the host key (no jump host).
- The ssh process exists **only while the modal is open** — closing it (or the browser) drops the
  socket, and the bridge kills the pty, freeing the RAM.
- Auth: the session cookie gates the socket, and a browser `Origin`, if present, must be the panel
  host or localhost (anti-CSWSH; `SameSite=Lax` already blocks the cookie cross-site).

## Live updates (no refresh)
Status streams into the UI without reloading, driven by `app.js`:
- **Dashboard** polls `GET /api/vps` every **4s** and updates each matching card/row's status tag
  and the `R/N running` count in place. If the set of instances changes (a deploy added one, a
  destroy removed one), it reloads **once** so the new/removed row appears.
- **Detail page** polls `GET /vps/:name/status` every **3s**, updating the status tag and which
  power controls are shown, and enabling the web-terminal button once the VPS is truly `running`.
  When a VPS goes transitional → `running` (specs like the SSH domain/IP fill in only then), the
  page reloads **once** to show them (unless the terminal modal is open).
- **Lifecycle actions** (stop / start / restart / terminate) are submitted with **AJAX** and a
  loading label on the button — no page navigation. **Terminate** removes the row/card live (and
  on the detail page returns to the dashboard).
- **Confirmations** use a **styled in-page dialog** — never the native `confirm()`/`alert()`.

## Security
- **Password**: PBKDF2-HMAC-SHA256, stored `0600` at `state/panel-auth.json`. Never plaintext, never in `.env`. Set once on first run (setup page).
- **Sessions**: random token, in-memory. Cookie `mms_session` — `HttpOnly; Secure; SameSite=Lax; Domain=.$DOMAIN`.
- **CSRF**: authed POSTs (deploy/destroy, rename, restart/stop/start, logout) use a session-bound token; pre-auth forms (login/setup) use a double-submit `mms_csrf` cookie (`SameSite=Strict`). POSTs verify it.
- **Rate limiting**: 5 failed logins per IP → 5-minute lockout. Behind cloudflared the socket peer is always `127.0.0.1`, so the **real client IP** is read from `CF-Connecting-IP` / `X-Forwarded-For`.
- **Exposure**: binds `127.0.0.1` only; the internet reaches it via Cloudflare. The Mac itself keeps only `:22` open (pf). Monitoring is separate — the Beszel hub has its own login and is routed directly by cloudflared.
- **Input**: VPS names validated (`^[A-Za-z0-9._-]+$`); bundle whitelisted; specs clamped — nothing from a form is passed unchecked to `tart`/shell.

## Working on the UI
Edit files under `web/` — no Swift recompile needed to restyle (templates + CSS + JS are read
at request time). To preview a change:
```bash
# run the panel locally
( cd control-plane && swift build ) && ./control-plane/.build/debug/macserver-panel --port 8093 &
# render it and look (don't just grep the HTML)
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --screenshot=/tmp/panel.png --window-size=1280,900 http://127.0.0.1:8093/
```
For auth-gated pages, create an admin via `POST /setup` and pass the session cookie (it's
`Secure`, so read it from the `Set-Cookie` header and send it with `curl -b`).

## Persistence
Installed as a **LaunchDaemon** (`io.macmultiserver.panel`, runs as your user) so it survives
reboot with no GUI login. The repo must live **outside** `~/Desktop`/`~/Documents`/`~/Downloads`
(TCC-protected — launchd can't load a binary from there). See [setup.md](setup.md).
