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
  dashboard.html           deploy form (bundle cards) + servers list
control-plane/Sources/Panel/
  main.swift               args + start server
  Routes.swift             routes, sessions, auth checks, CSRF, rate-limit
  Pages.swift              tiny renderer: load web/<tpl>, substitute {{TOKENS}}, inject fragments
  Store.swift              read state/*.json, list bundles (templates/*/meta.json), call ./mms
  Auth.swift               PBKDF2-HMAC-SHA256 admin credential
  Config.swift             read .env
```
Templates use `{{TOKEN}}` placeholders; `Pages.swift` fills them and injects the data-driven
bits (bundle cards, server cards, error/notice blocks). Swift serves `/style.css` and `/app.js`
as static files.

## Routes
| Method · path | Purpose |
|---|---|
| `GET /` | authed → 302 `/dashboard`; else serve login (or setup on first run) + a CSRF cookie |
| `GET /dashboard` | the dashboard; **302 to `/` if not signed in** |
| `GET /style.css`, `GET /app.js` | static assets from `web/` |
| `POST /setup` | first-run: create admin (CSRF-checked), then session + 302 `/dashboard` |
| `POST /login` | verify (CSRF-checked, rate-limited), session + 302 `/dashboard` |
| `POST /logout` | drop session, clear cookie, 302 `/` |
| `POST /deploy` | authed + CSRF → `./mms deploy …` (background), 302 `/dashboard` |
| `POST /destroy` | authed + CSRF → `./mms destroy <name>`, 302 `/dashboard` |

(`monitor.$DOMAIN` is **not** a panel route — cloudflared sends it straight to the Beszel hub, which has its own login. See [monitoring.md](monitoring.md).)

## Security
- **Password**: PBKDF2-HMAC-SHA256, stored `0600` at `state/panel-auth.json`. Never plaintext, never in `.env`. Set once on first run (setup page).
- **Sessions**: random token, in-memory. Cookie `mms_session` — `HttpOnly; Secure; SameSite=Lax; Domain=.$DOMAIN`.
- **CSRF**: authed actions (deploy/destroy/logout) use a session-bound token; pre-auth forms (login/setup) use a double-submit `mms_csrf` cookie (`SameSite=Strict`). POSTs verify it.
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
