# Control plane (the web panel)

The panel is a **native Swift binary** (`macserver-panel`) that renders the UI **server-side**
and drives the same `./mms` engine the CLI uses. It's login-gated, binds `127.0.0.1`, and is
reached only through Cloudflare (`panel.$DOMAIN`).

## Why SSR (not a JS SPA)
Server-side rendering keeps the attack surface small for a panel that can create/destroy
servers: a few form routes instead of a JSON API, minimal client JS, and output escaping in
one place. The UI still lives in real files (below), so design is easy to work on.

## Layout
```
web/                       ← the UI (edit here; no recompile to restyle)
  style.css                shared styles (light + spring-green, matched to vantis.sh)
  app.js                   progressive enhancement: password eye, live match, bundle select
  setup.html               first-run: create admin
  login.html               sign in
  dashboard.html           deploy form (bundle cards) + 3-column servers grid
  vps.html                 per-VPS detail page: specs, SSH-by-domain, controls, web terminal
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
| `GET /dashboard` | the dashboard (3-column server grid + deploy form); **302 to `/` if not signed in** |
| `GET /vps/:name` | per-VPS **detail page** (specs, SSH, controls, terminal); 302 if not signed in / no such VPS |
| `GET /style.css`, `GET /app.js` | static assets from `web/` |
| `GET /logos/:file`, `GET /vendor/:file` | bundle logos + vendored xterm.js (basename-only, whitelisted extensions) |
| `POST /setup` | first-run: create admin (CSRF-checked), then session + 302 `/dashboard` |
| `POST /login` | verify (CSRF-checked, rate-limited), session + 302 `/dashboard` |
| `POST /logout` | drop session, clear cookie, 302 `/` |
| `POST /deploy` | authed + CSRF → `./mms deploy …` (background), 302 `/dashboard` |
| `POST /destroy` | authed + CSRF → `./mms destroy <name>`, 302 `/dashboard` |
| `POST /vps/:name/rename` | authed + CSRF → set the human **Name tag** (id stays `vps-N`), 302 back |
| `POST /vps/:name/restart` | authed + CSRF → `./mms restart <name>`, 302 back |
| `POST /vps/:name/stop` | authed + CSRF → `./mms stop <name>`, 302 back |
| `POST /vps/:name/start` | authed + CSRF → `./mms start <name>`, 302 back |
| `GET /vps/:name/term` | **WebSocket** web terminal — authed + Origin-checked; one ssh pty per connection |

(`monitor.$DOMAIN` is **not** a panel route — cloudflared sends it straight to the Beszel hub, which has its own login. See [monitoring.md](monitoring.md).)

## VPS detail page (`/vps/:name`)
An AWS-style instance page rendered from `web/vps.html`:
- **Specs** — image (bundle base OS, e.g. Ubuntu 24.04 LTS), bundle, vCPU / MB / GB, SSH domain,
  host-only IP, created time.
- **SSH by domain** — the `ssh admin@vpsN.$DOMAIN` command with a copy button, plus the one-time
  `~/.ssh/config` cloudflared snippet (`Host *.$DOMAIN` / `ProxyCommand cloudflared access ssh
  --hostname %h`). No IP is shown to a tenant. (If Cloudflare keys aren't set, it falls back to the
  raw IP for local use.)
- **Name tag** — rename the server (AWS-style, ≤60 chars). The **id** stays `vps-N`; the label is
  what the dashboard and page title show.
- **Controls** — Restart (always), Stop (when running) / Start (when stopped), and a Danger-zone
  Terminate. These call the same `./mms` lifecycle the CLI uses.
- **Web terminal** — a button opens a modal terminal (below).

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
